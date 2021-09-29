RSpec.describe "Interscript#transliterate_each" do
  before :example do
    $compiler = Interscript::Interpreter
  end

  it "works" do
    s = stage {
      sub "X", any("abcd")
      sub "Y", any("defg")
      sub "Z", any("ghij")
    }

    expect(s.("XYZ", each: true).take(5)).to eq(%w[adg adh adi adj aeg])
  end

  # it "supports a certain scenario" do
  #   s = stage {
  #    sub "X", any(["x", any("abc"), "d"])
  #   }
  #
  #   expect(s.("X", each: true).to_a).to eq(%w[x x x a b c d d d])
  # end
end
