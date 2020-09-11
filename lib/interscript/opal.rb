module Interscript
  module Opal
    ALPHA_REGEXP = '\p{L}'

    def mkregexp(regexpstring)
      flags = 'u'
      if regexpstring.include? "(?i)"
        regexpstring = regexpstring.gsub("(?i)", "").gsub("(?-i)", "")
        flags = 'ui'
      end
      Regexp.new("/#{regexpstring}/#{flags}")
    end

    def sub_replace(string, pos, size, repl)
      string[0, pos] + repl + string[pos + size..-1]
    end

    def external_processing(mapping, string)
      string
    end

    def load_map_json(name, json)
      `Opal.global.InterscriptMaps[#{name}] = #{json}`
    end

  end
end
