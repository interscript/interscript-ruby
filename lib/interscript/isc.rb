# frozen_string_literal: true

require "parslet"

module Interscript
  module Isc
    autoload :Parser, "interscript/isc/parser"
    autoload :Transform, "interscript/isc/transform"
    autoload :DocumentBuilder, "interscript/isc/document_builder"
    autoload :Grammar, "interscript/isc/grammar"
    autoload :Items, "interscript/isc/items"
    autoload :Codemod, "interscript/isc/codemod"
    autoload :NodeAdapter, "interscript/isc/node_adapter"

    SCHEMA_VERSION = 1

    def self.parse(source, filename: nil)
      Parser.parse(source, filename: filename)
    end

    def self.load_file(path)
      parse(File.read(path, encoding: "UTF-8"), filename: path)
    end
  end
end
