# frozen_string_literal: true

# Plane runtime (kind=plane artifacts): one ONNX graph over
# (input_ids, plane_ids), K mask-predict passes, per-char majority vote,
# byte-exact render. Fixture graph cycles classes so the K-pass loop is
# observable: class(plane) = (plane + 1) % n_classes.

RSpec.describe Interscript::ML::PlaneModel do
  let(:zip) { File.expand_path("../fixtures/tiny-plane.zip", __dir__) }

  describe ".from_zip" do
    it "verifies member sha256s and rejects tampering" do
      expect { described_class.from_zip(File.read(zip)) }.not_to raise_error
      require 'zip'
      require 'stringio'
      src = Zip::File.open(zip)
      bad = Zip::File.open_buffer(StringIO.new(File.binread(zip)))
      bad_entry = bad.entries.find { |e| e.name == 'plane.onnx' }
      tampered = bad_entry.get_input_stream.read + "x"
      buf = Zip::OutputStream.write_buffer do |out|
        src.entries.each do |e|
          out.put_next_entry(e.name)
          out.write(e.name == 'plane.onnx' ? tampered : e.get_input_stream.read)
        end
      end.string
      expect { described_class.from_zip(buf) }.to raise_error(Interscript::ML::IMF::FormatError, /sha256 mismatch/)
    end
  end

  describe "#translate" do
    it "runs the K-pass loop and renders one class per char" do
      m = described_class.from_zip(File.read(zip))
      expect(m.k_passes).to eq(2)
      # MASK(4) -> 1 -> 2: with k=2 every position lands on damma
      expect(m.translate("كتب")).to eq("كُتُبُ")
    end

    it "keeps the skeleton byte-exact (round-trip)" do
      m = described_class.from_zip(File.read(zip))
      text = "الرجل ثائر في البيت الكبير"
      out = m.translate(text)
      plain = out.chars.reject { |c| m.classes.include?(c) }.join
      expect(plain).to eq(text)
    end
  end

  describe ".render_plane" do
    it "renders classes onto the skeleton" do
      expect(Interscript::ML.render_plane("كتب", ["", "َ", "ُ"])).to eq("كتَبُ")
    end
  end
end

RSpec.describe Interscript::ML::PlaneModel, "#translate preserve_diacritics" do
  let(:zip) { File.expand_path("../fixtures/tiny-plane.zip", __dir__) }
  let(:m) { described_class.from_zip(File.read(zip)) }
  let(:plain_of) { ->(s) { s.chars.reject { |c| m.classes.include?(c) }.join } }

  it "default path unchanged by flag" do
    expect(m.translate("كتب")).to eq(m.translate("كتب", preserve_diacritics: false))
  end

  it "fully labeled input round-trips byte-exactly" do
    labeled = "كُتُبُ"
    expect(m.translate(labeled, preserve_diacritics: true)).to eq(labeled)
  end

  it "partial input keeps user classes and fills the rest" do
    out = m.translate("كُتب", preserve_diacritics: true)
    expect(out).to start_with("كُ")
    expect(plain_of.call(out)).to eq("كتب")
  end

  it "leading marks round-trip without anchors leaking" do
    out = m.translate("ُكتب", preserve_diacritics: true)
    expect(out[0]).to eq("ُ")
    expect(out).not_to include("\x00")
    expect(plain_of.call(out)).to eq("كتب")
  end

  it "unknown cluster still round-trips byte-exactly" do
    out = m.translate("كُْتب", preserve_diacritics: true)
    expect(out).to include("كُْ")
    expect(plain_of.call(out)).to eq("كتب")
  end
end
