RSpec.describe Interscript::Detector do
  it "should return valid data when map_pattern is selected and multiple is true" do
    out = Interscript.detect(
      "привет", "privet",
      map_pattern: "icao-ukr-*",
      multiple: true,
      compiler: Interscript::Compiler::Ruby
    )
    expected = {"icao-ukr-Cyrl-Latn-9303" => 1.0}
    expect(out).to eq(expected)
  end

  it "should return valid data when map_pattern isn't selected and multiple is false" do
    out = Interscript.detect("привет", "privet", compiler: Interscript::Compiler::Ruby)
    expect(out).to be_a(String)
  end

  it "should return valid data when map_pattern isn't selected and multiple is true" do
    out = Interscript.detect(
      "привет", "privet", 
      multiple: true,
      compiler: Interscript::Compiler::Ruby,
    )
    expect(out).to be_a(Hash)
    expect(out.keys.all? { |i| i.class == String }).to be true
    expect(out.values.all? { |i| Numeric === i }).to be true
  end
end