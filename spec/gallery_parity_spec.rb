# Gallery parity: the same conversion table the TypeScript example
# gallery (interscript-ts/examples/) asserts. Same bytes from every
# runtime - demonstrated, not claimed. Adding a case = one line.

require "interscript"
GALLERY = {
  "Антон Олегович" => "Anton Olehovych",
  "Соломія" => "Solomiia",
  "Київ" => "Kyiv"
}.freeze

RSpec.describe "gallery parity with the TypeScript examples" do
  GALLERY.each do |input, expected|
    it "bgnpcgn-ukr-Cyrl-Latn-2019: #{input} -> #{expected}" do
      expect(Interscript.transliterate("bgnpcgn-ukr-Cyrl-Latn-2019", input)).to eq(expected)
    end
  end
end
