require "interscript"

RSpec.describe Interscript::Stdlib::Functions do
  it "autoloads the Functions namespace from stdlib.rb" do
    expect(described_class).to eq(Interscript::Stdlib::Functions)
  end

  it "lists rababa and secryst as available functions" do
    expect(Interscript::Stdlib.available_functions).to include(:rababa, :secryst, :rababa_reverse)
  end

  it "reverse-maps rababa to rababa_reverse" do
    expect(Interscript::Stdlib.reverse_function[:rababa]).to eq(:rababa_reverse)
    expect(Interscript::Stdlib.reverse_function[:rababa_reverse]).to eq(:rababa)
  end

  describe ".title_case" do
    it "capitalizes the first letter of each word" do
      expect(described_class.title_case("hello world")).to eq("Hello World")
    end
  end

  describe ".downcase" do
    it "lowercases everything when no separator given" do
      expect(described_class.downcase("HELLO")).to eq("hello")
    end
  end

  describe ".compose / .decompose" do
    it "round-trips through NFC and NFD" do
      composed = described_class.compose("café")
      expect(composed).to eq("café")
      decomposed = described_class.decompose(composed)
      expect(decomposed).to eq("café")
    end
  end

  describe ".separate / .unseparate" do
    it "round-trips" do
      separated = described_class.separate("abc")
      expect(separated).to eq("a b c")
      expect(described_class.unseparate(separated)).to eq("abc")
    end
  end

  describe ".rababa_reverse" do
    it "strips harakat without loading the model" do
      result = described_class.rababa_reverse("كَتَبَ")
      expect(result).to eq("كتب")
    end

    it "does not require the config kwarg" do
      expect { described_class.rababa_reverse("كَتَبَ") }.not_to raise_error
    end
  end

  describe ".rababa (without registered config)" do
    it "raises ExternalUtilError naming the missing config" do
      # A name that cannot be registered: the sweep's load path puts the
      # monorepo's rababa-configs in scope, where "default" exists.
      expect { described_class.rababa("كتب", config: "no-such-config") }.to raise_error(
        Interscript::ExternalUtilError,
        /No rababa config registered under 'no-such-config'/
      )
    end
  end

  describe ".secryst (built-in ML runtime)" do
    it "translates through Interscript::ML with no external gem" do
      zip = File.expand_path("../interscript/fixtures/tiny-imf.zip", __dir__)
      skip "tiny IMF fixture missing" unless File.exist?(zip)

      out = described_class.secryst("test", model: zip)
      expect(out).to be_a(String)
    end
  end
end

RSpec.describe Interscript::Stdlib::Functions::RababaAdapter do
  it "is autoloaded from a separate file" do
    expect(described_class.name).to eq("Interscript::Stdlib::Functions::RababaAdapter")
  end

  describe ".reverse" do
    it "strips harakat without touching the model" do
      expect(described_class.reverse("كَتَبَ")).to eq("كتب")
    end
  end
end

RSpec.describe Interscript::Stdlib::Functions::SecrystAdapter do
  it "is autoloaded from a separate file" do
    expect(described_class.name).to eq("Interscript::Stdlib::Functions::SecrystAdapter")
  end
end

RSpec.describe Interscript::ML::Provisioning do
  describe "candidate paths" do
    it "prefers interscript-ml locations, keeping secryst paths as legacy fallbacks" do
      paths = described_class.candidate_paths
      expect(paths.first).to eq(File.join(Dir.home, ".local/share/interscript-ml"))
      expect(paths).to include(File.join(Dir.home, ".local/share/secryst"))
      expect(paths.join(" ")).not_to match(%r{/var/lib/secryst})
    end
  end
end
