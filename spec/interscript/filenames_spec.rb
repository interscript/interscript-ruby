require "spec_helper"
require "iso-639-data"
require "iso-15924"

RSpec.describe "filenames" do
  valid_authcodes = YAML.load(File.read("authority_codes.yaml")).keys
  re = /\A(\w+)-(\w+)-(\w+)-(\w+)-/

  Dir["maps/*.yaml"].each do |i|
    n = File.basename(i, ".yaml")

    it "name #{n} is valid?" do
      expect(n =~ re).to be_truthy
      authcode, lang, source_script, target_script = $1, $2, $3, $4
      expect(valid_authcodes).to include authcode
      expect(Iso639Data.valid?(lang)).to be true
      expect(Iso15924.valid?(source_script)).to be true
      expect(Iso15924.valid?(target_script)).to be true
    end
  end
end
