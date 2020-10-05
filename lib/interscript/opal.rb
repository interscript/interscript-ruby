require "onigmo"
require "onigmo/core_ext"

# Increase this if there are out-of-memory errors. This setting is
# tested to be big enough to handle all the maps provided.
Onigmo::FFI.library.memory.grow(128)

module Interscript
  module Opal
    def mkregexp(regexpstring)
      @cache ||= {}
      if s = @cache[regexpstring]
        if s.class == Onigmo::Regexp
          # Opal-Onigmo stores a variable "lastIndex" mimicking the JS
          # global regexp. If we want to reuse it, we need to reset it.
          s.reset
        else
          s
        end
      else
        # JS regexp is more performant than Onigmo. Let's use the JS
        # regexp wherever possible, but use Onigmo where we must.
        # Let's allow those characters to happen for the regexp to be
        # considered compatible: ()|.*+?{} ** BUT NOT (? **.
        if /[\\$^\[\]]|\(\?/.match?(regexpstring)
          # Ruby caches its regexps internally. We can't GC. We could
          # think about freeing them, but we really can't, because they
          # may be in use.

          # Uncomment those to keep track of Onigmo/JS regexp compilation.
          # print '#'
          @cache[regexpstring] = Onigmo::Regexp.new(regexpstring)
        else
          # print '.'
          @cache[regexpstring] = Regexp.new(regexpstring)
        end
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
