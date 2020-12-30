require "interscript/version"

module Interscript
  class << self
    # Transliterates the string.
    def transliterate(system_code, string, maps={})
      # The current best implementation is Interpreter
      impl = Interscript::Interpreter

      maps[system_code] ||= impl.(system_code)
      maps[system_code].(string)
    end
  end
end

require 'interscript/stdlib'

require "interscript/compiler"
require "interscript/interpreter"

require 'interscript/dsl'
require 'interscript/node'
