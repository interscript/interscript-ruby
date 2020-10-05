require "onigmo"
require "onigmo/core_ext"

Onigmo::FFI.library.memory.grow(4096)

module Interscript
  module Opal
    def mkregexp(regexpstring)
      # Is it a regexp?
      if regexpstring.match?(/[\\\[\]{}$^()*+?.|]/)
        # Ruby caches its regexps internally. We can't GC. We could think about
        # freeing them, but we really can't, because they may be in use.
        @cache ||= {}
        @cache[regexpstring] ||= Onigmo::Regexp.new(regexpstring)
        # Let's try at least removing the JS pointer that may hamper compatibility.
        # Before: 793 fails, after: 708 fails
        @cache[regexpstring].reset
      else
        regexpstring
      end
    end

    def sub_replace(string, pos, size, repl)
      string[0, pos] + repl + string[pos + size..-1]
    end

    def external_processing(mapping, string)
      string
    end

    # name is unused
    def load_map_json(name, json)
      JSON.load(json).each do |k,v|
        `Opal.global.InterscriptMaps[#{k}] = #{JSON.dump(v)}`
      end
    end

  end
end

class String
  # Opal has a wrong implementation of String#unicode_normalize
  def unicode_normalize
    self.JS.normalize
  end
end
