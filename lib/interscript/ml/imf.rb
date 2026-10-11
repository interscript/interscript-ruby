require "yaml"
require "digest/sha2"
require "fileutils"
require "open-uri"

module Interscript::ML
  # Interscript Model Format v1 — the byte-level runtime contract shared
  # with the Python (interscript-ml) and TypeScript (npm: secryst)
  # runtimes. Token ids follow the canonical ByT5 table: byte b -> b+3,
  # trailing EOS; pad=0, unk=2. Ids are NOT raw byte values.
  module IMF
    BYTE_OFFSET = 3
    PAD_ID = 0
    EOS_ID = 1
    UNK_ID = 2

    DEFAULT_INDEX_URL = "https://github.com/interscript/interscript-models/releases/download/index-v10/models-index.yaml"

    class FormatError < StandardError; end
    class RegistryError < StandardError; end

    class << self
      def require_zip!
        Interscript::ML.require_optional!("rubyzip", feature: "zip")
      end

      def encode(text)
        text.bytes.map { |b| b + BYTE_OFFSET } + [EOS_ID]
      end

      # Seq2seq output contract: models trained on multi-reference
      # corpora emit '/'-separated alternates per token; the runtime
      # returns the primary choice only.
      def first_alternates(text)
        text.split.map { |tok| tok.split('/', 2).first }.join(' ')
      end

      def decode(token_ids)
        out = +""
        token_ids.each do |token|
          break if token == EOS_ID
          next if token == PAD_ID || token == UNK_ID
          out << ((token - BYTE_OFFSET) % 256).chr
        end
        out.force_encoding(Encoding::UTF_8)
      end

      def manifest(zip_path)
        require_zip!
        Zip::File.open(zip_path) do |zf|
          raise FormatError, "missing metadata.yaml" unless zf.find_entry("metadata.yaml")
          meta = YAML.safe_load(zf.read("metadata.yaml"), permitted_classes: [], aliases: false)
          raise FormatError, "unsupported format: #{meta["format"].inspect}" if meta["format"] != "imf-v1"
          if meta["tokenizer"] != "bytes"
            raise FormatError, "tokenizer #{meta["tokenizer"].inspect}: this runtime is byte-level only"
          end
          %w[encoder.onnx decoder.onnx].each do |required|
            raise FormatError, "missing #{required}" unless zf.find_entry(required)
          end
          meta
        end
      end

      # Reads every .onnx member after verifying its sha256 against the
      # manifest — corrupt zips fail loudly, before any session loads.
      def verify_and_read(zip_path)
        meta = manifest(zip_path)
        sha = meta.fetch("sha256", {})
        graphs = {}
        require_zip!
        Zip::File.open(zip_path) do |zf|
          zf.entries.select { |e| e.name.end_with?(".onnx") }.each do |entry|
            recorded = sha[entry.name]
            raise FormatError, "#{entry.name} is not covered by metadata sha256" unless recorded
            bytes = entry.get_input_stream.read
            actual = Digest::SHA256.hexdigest(bytes)
            if actual != recorded
              raise FormatError, "#{entry.name} sha256 mismatch: zip has #{actual}, metadata says #{recorded}"
            end
            graphs[entry.name] = bytes
          end
        end
        graphs
      end

      def cache_dir
        ENV["INTERSCRIPT_ML_CACHE"] || ENV["SECRYST_CACHE"] || File.join(Dir.home, ".cache", "interscript-ml")
      end

      # models.yaml resolution: cache hit (re-verified), or download ->
      # verify whole-file sha256 -> atomic install into the cache.
      # Entries with `parts` (GitHub's 2 GiB per-asset cap) are streamed
      # in order, each part sha256-verified as it lands, then the
      # assembled file is checked against the whole-file sha256.
      def resolve(model_id, index_url: nil)
        source = index_url || ENV["INTERSCRIPT_ML_INDEX"] || ENV["SECRYST_INDEX"] || DEFAULT_INDEX_URL
        entries = load_index(source)
        entry = entries[model_id]
        raise RegistryError, "unknown model id #{model_id.inspect} (known: #{entries.keys.sort})" unless entry

        target = File.join(cache_dir, "models", model_id, entry["filename"])
        if File.file?(target) && Digest::SHA256.file(target).hexdigest == entry["sha256"]
          return target
        end

        FileUtils.mkdir_p(File.dirname(target))
        tmp = target + ".part.#{Process.pid}"
        if entry["parts"]
          download_parts(entry, tmp)
        else
          channel = entry["url"]
          if channel.start_with?("file://")
            FileUtils.cp(channel.sub(%r{\Afile://}, ""), tmp)
          else
            URI.open(channel) { |remote| IO.copy_stream(remote, tmp) }
          end
        end
        actual = Digest::SHA256.file(tmp).hexdigest
        unless actual == entry["sha256"]
          File.delete(tmp)
          raise RegistryError, "downloaded #{entry["filename"]} sha256 mismatch: got #{actual}, index says #{entry["sha256"]}"
        end
        File.rename(tmp, target)
        target
      end

      private

      def download_parts(entry, tmp)
        File.open(tmp, "wb") do |out|
          entry["parts"].each_with_index do |part, index|
            digest = Digest::SHA256.new
            source = part["url"].start_with?("file://") ? part["url"].sub(%r{\Afile://}, "") : part["url"]
            open_stream = lambda do |io|
              while (chunk = io.read(1024 * 1024))
                out.write(chunk)
                digest.update(chunk)
              end
            end
            if part["url"].start_with?("file://")
              File.open(source, "rb", &open_stream)
            else
              URI.open(source, "rb", &open_stream)
            end
            unless digest.hexdigest == part["sha256"]
              raise RegistryError, "part #{index} of #{entry["filename"]} sha256 mismatch: got #{digest.hexdigest}, index says #{part["sha256"]}"
            end
          end
        end
      rescue StandardError
        File.delete(tmp) if File.file?(tmp)
        raise
      end

      def load_index(source)
        text = if source.start_with?("http://", "https://")
          fetch_index_with_sidecar(source)
        else
          File.read(source)
        end
        raw = YAML.safe_load(text, permitted_classes: [], aliases: false)
        raise RegistryError, "index must have version: 1" if raw["version"] != 1
        raw.fetch("models", {})
      end
      public :load_index

      # HTTP sources must ship a sibling .sha256 sidecar; verify the
      # body against it before parsing (GitHub Releases index assets do).
      def fetch_index_with_sidecar(source)
        body = URI.open(source, "rb") { |remote| remote.read }
        sidecar =
          begin
            URI.open("#{source}.sha256") { |remote| remote.read }
          rescue OpenURI::HTTPError => e
            raise RegistryError, "index sha256 sidecar missing: #{source}.sha256 (#{e.message})"
          end
        expected = sidecar.to_s.strip.split(/\s+/).first.to_s
        unless expected.match?(/\A[0-9a-fA-F]{64}\z/)
          raise RegistryError, "index sha256 sidecar malformed: #{source}.sha256"
        end
        actual = Digest::SHA256.hexdigest(body)
        unless actual == expected.downcase
          raise RegistryError, "index sha256 mismatch: got #{actual}, sidecar says #{expected.downcase}"
        end
        body.force_encoding(Encoding::UTF_8)
      end
    end
  end
end
