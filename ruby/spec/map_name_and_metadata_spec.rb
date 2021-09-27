require "spec_helper"
require "iso-639-data"
require "iso-15924"

RSpec.describe "map names and metadata" do
  valid_authcodes = YAML.load(File.read(__dir__+"/authority_codes.yaml")).keys

  Interscript.maps.each do |n|
    context n do
      parts = n.split('-', 5)
      authcode, lang, source_script, target_script, id = parts
      map = Interscript.parse(n)

      it "has a valid name" do
        expect(parts.count).to be 5
        expect(valid_authcodes).to include authcode
        expect(Iso639Data.valid?(lang)).to be true
        expect(Iso15924.valid?(source_script)).to be true
        expect(Iso15924.valid?(target_script)).to be true
      end

      it "has matching metadata" do
        expect(map.metadata[:authority_id]).to eq authcode
        expect(map.metadata[:source_script]).to eq source_script
        expect(map.metadata[:destination_script]).to eq target_script
        expect(map.metadata[:id]).to eq id
      end

      it "has a correct language in the metadata" do
        m_auth, m_lang = map.metadata[:language].split(':', 2)

        expect(lang).to eq m_lang

        case m_auth
        when 'iso-639-2'
          expect(Iso639Data.iso_639_2.key? m_lang).to be true          
        when 'iso-639-3'
          expect(Iso639Data.iso_639_3.key? m_lang).to be true
        else
          raise "#{m_auth} is an invalid authority for #{lang} - iso-639-2 or 3 expected"
        end
      end
    end
  end
end
