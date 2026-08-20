class Interscript::Stdlib
  module Functions
    autoload :RababaAdapter, "interscript/stdlib/functions/rababa_adapter"
    autoload :SecrystAdapter, "interscript/stdlib/functions/secryst_adapter"

    def self.title_case(output, word_separator: " ")
      output = output.gsub(/^(.)/, &:upcase)
      output = output.gsub(/#{word_separator}(.)/, &:upcase) unless word_separator == ""
      output
    end

    def self.downcase(output, word_separator: nil)
      if word_separator
        output = output.gsub(/^(.)/, &:downcase)
        output.gsub(/#{word_separator}(.)/, &:downcase) unless word_separator == ""
      else
        output.downcase
      end
    end

    def self.compose(output, _: nil)
      output.unicode_normalize(:nfc)
    end

    def self.decompose(output, _: nil)
      output.unicode_normalize(:nfd)
    end

    def self.separate(output, separator: " ")
      output.split("").join(separator)
    end

    def self.unseparate(output, separator: " ")
      output.split(separator).join("")
    end

    def self.secryst(output, model:)
      SecrystAdapter.call(output, model: model)
    end

    def self.rababa(output, config:)
      RababaAdapter.call(output, config: config)
    end

    def self.rababa_reverse(output, config: nil)
      RababaAdapter.reverse(output)
    end
  end
end
