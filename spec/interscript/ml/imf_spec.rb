require "spec_helper"
require "zip"
require 'interscript/ml'
require 'fileutils'
require 'tmpdir'
require 'json'

RSpec.describe Interscript::ML::IMF do
  it 'uses the canonical ByT5 table (byte + 3, trailing EOS)' do
    expect(described_class.encode('rok')).to eq([117, 114, 110, 1])
    expect(described_class.decode([117, 114, 110])).to eq('rok')
    expect(described_class.decode([117, 1, 114])).to eq('r')
  end

  describe 'with the tiny IMF fixture zip' do
    let(:zip_path) { File.expand_path('../fixtures/tiny-imf.zip', __dir__) }

    it 'parses the manifest and verifies graph checksums' do
      meta = described_class.manifest(zip_path)
      expect(meta['format']).to eq('imf-v1')
      expect(meta['tokenizer']).to eq('bytes')
      graphs = described_class.verify_and_read(zip_path)
      expect(graphs.keys.sort).to eq(['decoder.onnx', 'encoder.onnx'])
    end

    it 'loads sessions from verified bytes' do
      model = Interscript::ML::Byt5Onnx.new(zip_path)
      expect(model.id).to eq('tiny-1.0')
    end

    it 'decodes a real zip against the shared golden set', :e2e do
      zip = ENV['SECRYST_E2E_ZIP']
      golden = ENV['SECRYST_GOLDEN']
      skip 'set SECRYST_E2E_ZIP and SECRYST_GOLDEN for the end-to-end run' unless zip && golden
      translator = Interscript::ML::Translator.new(model_file: zip)
      ok = 0
      total = 0
      File.readlines(golden).each do |line|
        row = JSON.parse(line)
        total += 1
        ok += 1 if translator.translate(row['input'], max_seq_length: 128) == row['output']
      end
      expect(ok).to eq(total)
    end
  end

  it 'rejects a tampered zip loudly' do
    Dir.mktmpdir do |tmp|
      source = File.expand_path('../fixtures/tiny-imf.zip', __dir__)
      tampered = File.join(tmp, 'tampered.zip')
      require 'zip'
      Zip::File.open(source) do |src|
        Zip::File.open(tampered, create: true) do |dst|
          src.entries.each do |e|
            if e.name == 'encoder.onnx'
              dst.get_output_stream(e.name) { |io| io.write('corrupted-bytes') }
            else
              dst.get_output_stream(e.name) { |io| io.write(e.get_input_stream.read) }
            end
          end
        end
      end
      expect { described_class.verify_and_read(tampered) }
        .to raise_error(Interscript::ML::IMF::FormatError, /sha256 mismatch/)
    end
  end

  describe '.resolve' do
    it 'installs a verified copy into the cache from a local index' do
      Dir.mktmpdir do |tmp|
        channel = File.join(tmp, 'channel')
        FileUtils.mkdir_p(channel)
        zip_path = File.expand_path('../fixtures/tiny-imf.zip', __dir__)
        FileUtils.cp(zip_path, File.join(channel, 'tiny.zip'))
        require 'digest'
        index = File.join(tmp, 'models.yaml')
        File.write(index, <<~YAML)
          version: 1
          models:
            tiny-1.0:
              filename: tiny.zip
              url: file://#{channel}/tiny.zip
              sha256: #{Digest::SHA256.file(zip_path).hexdigest}
        YAML
        cache = File.join(tmp, 'cache')
        result = described_class.resolve('tiny-1.0', index_url: index) if false
        # env-based cache (the public API reads ENV at call time)
        ENV['SECRYST_CACHE'] = cache
        begin
          installed = described_class.resolve('tiny-1.0', index_url: index)
          expect(installed).to eq(File.join(cache, 'models', 'tiny-1.0', 'tiny.zip'))
          expect(File.file?(installed)).to be(true)
          FileUtils.rm_f(File.join(channel, 'tiny.zip'))
          expect(described_class.resolve('tiny-1.0', index_url: index)).to eq(installed)
        ensure
          ENV.delete('SECRYST_CACHE')
        end
      end
    end

    it 'raises for unknown ids' do
      Dir.mktmpdir do |tmp|
        index = File.join(tmp, 'models.yaml')
        File.write(index, "version: 1\nmodels: {}\n")
        expect { described_class.resolve('nope-1.0', index_url: index) }
          .to raise_error(Interscript::ML::IMF::RegistryError, /unknown model id/)
      end
    end

    it 'assembles and verifies split parts (the >2GiB GitHub cap path)' do
      Dir.mktmpdir do |tmp|
        channel = File.join(tmp, 'channel')
        FileUtils.mkdir_p(channel)
        zip_path = File.expand_path('../fixtures/tiny-imf.zip', __dir__)
        blob = File.binread(zip_path)
        part_a, part_b = blob[0, (blob.bytesize / 2 + 3)], blob[(blob.bytesize / 2 + 3)..]
        File.binwrite(File.join(channel, 'tiny.zip.part-00'), part_a)
        File.binwrite(File.join(channel, 'tiny.zip.part-01'), part_b)
        index = File.join(tmp, 'models.yaml')
        File.write(index, <<~YAML)
          version: 1
          models:
            tiny-1.0:
              filename: tiny.zip
              sha256: #{Digest::SHA256.hexdigest(blob)}
              parts:
                - url: file://#{channel}/tiny.zip.part-00
                  sha256: #{Digest::SHA256.hexdigest(part_a)}
                  size: #{part_a.bytesize}
                - url: file://#{channel}/tiny.zip.part-01
                  sha256: #{Digest::SHA256.hexdigest(part_b)}
                  size: #{part_b.bytesize}
        YAML
        cache = File.join(tmp, 'cache')
        ENV['SECRYST_CACHE'] = cache
        begin
          installed = described_class.resolve('tiny-1.0', index_url: index)
          expect(File.binread(installed)).to eq(blob)
          FileUtils.rm_f(File.join(channel, 'tiny.zip.part-00'))
          expect(described_class.resolve('tiny-1.0', index_url: index)).to eq(installed)
        ensure
          ENV.delete('SECRYST_CACHE')
        end
      end
    end

    it 'rejects a corrupt part by index' do
      Dir.mktmpdir do |tmp|
        channel = File.join(tmp, 'channel')
        FileUtils.mkdir_p(channel)
        zip_path = File.expand_path('../fixtures/tiny-imf.zip', __dir__)
        blob = File.binread(zip_path)
        part_a, part_b = blob[0, 7], blob[7..]
        File.binwrite(File.join(channel, 'tiny.zip.part-00'), part_a)
        File.binwrite(File.join(channel, 'tiny.zip.part-01'), part_b)
        index = File.join(tmp, 'models.yaml')
        File.write(index, <<~YAML)
          version: 1
          models:
            tiny-1.0:
              filename: tiny.zip
              sha256: #{Digest::SHA256.hexdigest(blob)}
              parts:
                - url: file://#{channel}/tiny.zip.part-00
                  sha256: #{"0" * 64}
                  size: #{part_a.bytesize}
                - url: file://#{channel}/tiny.zip.part-01
                  sha256: #{Digest::SHA256.hexdigest(part_b)}
                  size: #{part_b.bytesize}
        YAML
        ENV['SECRYST_CACHE'] = File.join(tmp, 'cache')
        begin
          expect { described_class.resolve('tiny-1.0', index_url: index) }
            .to raise_error(Interscript::ML::IMF::RegistryError, /part 0 .* sha256 mismatch/)
        ensure
          ENV.delete('SECRYST_CACHE')
        end
      end
    end
  end

  describe "index distribution contract" do
    it "pins DEFAULT_INDEX_URL to the exact current index release, never raw" do
      # exact pin (not index-v\d+): the default must resolve every model
      # the distribution contract has shipped, incl. static-int8 (v6).
      # Bump this spec WITH the constant, never ahead of it.
      expect(Interscript::ML::IMF::DEFAULT_INDEX_URL).to eq(
        "https://github.com/interscript/interscript-ml/releases/download/index-v7/models-index.yaml"
      )
      expect(Interscript::ML::IMF::DEFAULT_INDEX_URL).not_to include("raw.githubusercontent")
    end

    it "verifies the .sha256 sidecar on HTTP index fetches" do
      require "socket"
      body = "version: 1\nmodels: {}\n"
      good = Digest::SHA256.hexdigest(body)
      bad = "0" * 64

      serve = lambda do |sidecar, &blk|
        server = TCPServer.new("127.0.0.1", 0)
        port = server.addr[1]
        thread = Thread.new do
          loop do
            client = server.accept rescue break
            request = client.readline
            client.each_line { |line| break if line == "\r\n" }
            path = request.split(" ")[1]
            case path
            when "/models-index.yaml"
              client.write("HTTP/1.1 200 OK\r\nContent-Length: #{body.bytesize}\r\n\r\n#{body}")
            when "/models-index.yaml.sha256"
              if sidecar.nil?
                client.write("HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\n\r\n")
              else
                payload = "#{sidecar}  models-index.yaml\n"
                client.write("HTTP/1.1 200 OK\r\nContent-Length: #{payload.bytesize}\r\n\r\n#{payload}")
              end
            else
              client.write("HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\n\r\n")
            end
            client.close
          end
        end
        begin
          blk.call("http://127.0.0.1:#{port}/models-index.yaml")
        ensure
          server.close
          thread.join(5)
        end
      end

      serve.call(good) do |url|
        entries = Interscript::ML::IMF.load_index(url)
        expect(entries).to eq({})
      end
      serve.call(bad) do |url|
        expect {
          Interscript::ML::IMF.load_index(url)
        }.to raise_error(Interscript::ML::IMF::RegistryError, /index sha256 mismatch/)
      end
      serve.call(nil) do |url|
        expect {
          Interscript::ML::IMF.load_index(url)
        }.to raise_error(Interscript::ML::IMF::RegistryError, /index sha256/)
      end
    end
  end
end
