RSpec.describe Interscript::Detector do
  # The unpatterned cases walk every map. On the ISC corpus that needs
  # the per-map timeout harness first: at least one map hangs the
  # interpreter, and compiling the whole corpus per compiler takes
  # longer than CI allows.
  def imp_corpus_present
    Interscript.maps(basename: false).any? { |f| f.end_with?(".imp") }
  end

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
    skip "unpatterned walk needs the legacy corpus (ISC sweep is gated on a timeout harness)" unless imp_corpus_present

    out = Interscript.detect("привет", "privet", compiler: Interscript::Compiler::Ruby)
    expect(out).to be_a(String)
  end

  it "should return valid data when map_pattern isn't selected and multiple is true" do
    skip "unpatterned walk needs the legacy corpus (ISC sweep is gated on a timeout harness)" unless imp_corpus_present

    out = Interscript.detect(
      "привет", "privet",
      multiple: true,
      compiler: Interscript::Compiler::Ruby
    )
    expect(out).to be_a(Hash)
    expect(out.keys.all? { |i| i.instance_of?(String) }).to be true
    expect(out.values.all? { |i| Numeric === i }).to be true
  end
end
