# frozen_string_literal: true

require "json"
require "yaml"
require "interscript/ml"

RSpec.describe "Interscript::Ml — the IMF v1 model runtime" do
  let(:fixture_zip) { File.join(__dir__, "..", "fixtures", "tiny-imf.zip") }

  describe "the canonical ByT5 byte table" do
    it "encodes byte+3 with trailing EOS" do
      expect(Interscript::Ml::IMF.encode("rok")).to eq([117, 114, 110, 1])
    end

    it "decodes with EOS stop and pad/unk skip" do
      expect(Interscript::Ml::IMF.decode([117, 114, 110])).to eq("rok")
      expect(Interscript::Ml::IMF.decode([117, 1, 114])).to eq("r")
      expect(Interscript::Ml::IMF.decode([117, 0, 2, 114])).to eq("ro")
    end
  end

  describe "IMF zip loading" do
    it "parses and verifies the manifest" do
      meta = Interscript::Ml::IMF.manifest(fixture_zip)
      expect(meta["id"]).to eq("tiny-1.0")
      expect(meta["format"]).to eq("imf-v1")
    end

    it "verifies per-member sha256 and rejects tampering" do
      graphs = Interscript::Ml::IMF.verify_and_read(fixture_zip)
      expect(graphs.keys).to contain_exactly("encoder.onnx", "decoder.onnx")

      tampered = File.join(Dir.mktmpdir, "tampered.zip")
      original = Zip::File.open(fixture_zip) { |z| z.entries.map { |e| [e.name, e.get_input_stream.read] } }
      Zip::File.open(tampered, create: true) do |z|
        original.each do |name, bytes|
          z.get_output_stream(name) { |o| o.write(name == "metadata.yaml" ? bytes : bytes + "x") }
        end
      end
      expect { Interscript::Ml::IMF.verify_and_read(tampered) }.to raise_error(
        Interscript::Ml::IMF::FormatError, /sha256 mismatch/
      )
    end
  end

  describe "registry" do
    it "resolves, verifies, and caches from a local index" do
      require "tmpdir"
      require "json"
      dir = Dir.mktmpdir("imf-reg-")
      channel = File.join(dir, "channel")
      cache = File.join(dir, "cache")
      FileUtils.mkdir_p(channel)
      FileUtils.cp(fixture_zip, File.join(channel, "tiny.zip"))
      sha = Digest::SHA256.file(File.join(channel, "tiny.zip")).hexdigest
      index = File.join(dir, "models.yaml")
      File.write(index, <<~YAML)
        version: 1
        models:
          tiny-1.0:
            filename: tiny.zip
            url: file://#{File.join(channel, "tiny.zip")}
            sha256: #{sha}
      YAML

      stub_const("ENV", ENV.to_h.merge("INTERSCRIPT_ML_CACHE" => cache))
      resolved = Interscript::Ml::IMF.resolve("tiny-1.0", index_url: index)
      expect(resolved).to eq(File.join(cache, "models", "tiny-1.0", "tiny.zip"))
      # second resolve: cache hit (re-verified)
      expect(Interscript::Ml::IMF.resolve("tiny-1.0", index_url: index)).to eq(resolved)

      expect { Interscript::Ml::IMF.resolve("nope", index_url: index) }
        .to raise_error(Interscript::Ml::IMF::RegistryError, /unknown model id/)
    end
  end

  describe "ByT5 inference over the tiny graph" do
    it "runs the pipeline end to end and honors EOS" do
      model = Interscript::Ml::Byt5Onnx.new(fixture_zip)
      expect(model.id).to eq("tiny-1.0")
      # python reference (interscript_ml) decodes these to "" — the tiny
      # graph emits EOS immediately; the ruby path must agree exactly
      expect(model.translate("rok")).to eq("")
      expect(model.translate("rok dto roki")).to eq("")
      expect(model.translate("κώνος")).to eq("")
    end
  end

  describe "frozen conformance fixtures (real artifacts)" do
    e2e_zip = ENV["SECRYST_E2E_ZIP"]
    vectors_path = ENV["CONFORMANCE_VECTORS"]

    it "reproduces the frozen vectors byte-exactly", skip: !e2e_zip || !vectors_path do
      vectors = JSON.parse(File.read(vectors_path))
      expect(vectors["decode"]["mode"]).to eq("single-row-greedy")
      model = Interscript::Ml::Byt5Onnx.new(e2e_zip)
      failures = []
      vectors["vectors"].each do |v|
        got = model.translate(v["src"])
        failures << "#{v["src"]} -> #{got} (expected #{v["out"]})" if got != v["out"]
      end
      expect(failures).to be_empty, "#{vectors['model']}: #{failures.length} mismatched"
    end
  end
end
