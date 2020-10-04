require "onigmo"
require "onigmo/core_ext"

Onigmo::FFI.library.memory.grow(4096)

module Interscript
  module Opal
    def mkregexp(regexpstring)
      # Ruby caches its regexps internally. We can't GC. We could think about
      # freeing them, but we really can't, because they may be in use.
      @cache ||= {}
      @cache[regexpstring] ||= Onigmo::Regexp.new(regexpstring)
      # Let's try at least removing the JS pointer that may hamper compatibility.
      # Before: 793 fails, after: 708 fails
      @cache[regexpstring].reset
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
