require "spec_helper"
require "iso-639-data"

RSpec.describe "filenames" do
  valid_authcodes = YAML.load(File.read("authority_codes.yaml")).keys

  # From https://www.unicode.org/iso15924/iso15924-codes.html
  valid_script_codes = %w[Adlm Afak Aghb Ahom Arab Aran Armi Armn Avst Bali
    Bamu Bass Batk Beng Bhks Blis Bopo Brah Brai Bugi Buhd Cakm Cans Cari Cham
    Cher Chrs Cirt Copt Cpmn Cprt Cyrl Cyrs Deva Diak Dogr Dsrt Dupl Egyd Egyh
    Egyp Elba Elym Ethi Geok Geor Glag Gong Gonm Goth Gran Grek Gujr Guru Hanb
    Hang Hani Hano Hans Hant Hatr Hebr Hira Hluw Hmng Hmnp Hrkt Hung Inds Ital
    Jamo Java Jpan Jurc Kali Kana Khar Khmr Khoj Kitl Kits Knda Kore Kpel Kthi
    Lana Laoo Latf Latg Latn Leke Lepc Limb Lina Linb Lisu Loma Lyci Lydi Mahj
    Maka Mand Mani Marc Maya Medf Mend Merc Mero Mlym Modi Mong Moon Mroo Mtei
    Mult Mymr Nand Narb Nbat Newa Nkdb Nkgb Nkoo Nshu Ogam Olck Orkh Orya Osge
    Osma Palm Pauc Perm Phag Phli Phlp Phlv Phnx Piqd Plrd Prti Qaaa Qabx Rjng
    Rohg Roro Runr Samr Sara Sarb Saur Sgnw Shaw Shrd Shui Sidd Sind Sinh Sogd
    Sogo Sora Soyo Sund Sylo Syrc Syre Syrj Syrn Tagb Takr Tale Talu Taml Tang
    Tavt Telu Teng Tfng Tglg Thaa Thai Tibt Tirh Toto Ugar Vaii Visp Wara Wcho
    Wole Xpeo Xsux Yezi Yiii Zanb Zinh Zmth Zsye Zsym Zxxx Zyyy Zzzz]

  re = /\A(\w+)-(\w+)-(\w+)-(\w+)-/

  Dir["maps/*.yaml"].each do |i|
    n = File.basename(i, ".yaml")

    it "name #{n} is valid?" do
      expect(n =~ re).to be_truthy
      authcode, lang, source_script, target_script = $1, $2, $3, $4
      expect(valid_authcodes).to include authcode
      expect(ISO_639_DATA.valid?(lang)).to be true
      expect(valid_script_codes).to include source_script
      expect(valid_script_codes).to include target_script
    end
  end
end
