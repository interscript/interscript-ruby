# frozen_string_literal: true

require "parslet"
require "interscript/isc/grammar"

module Interscript
  module Isc
    # Entry point for parsing ISC source files.
    #
    #   tree = Interscript::Isc::Parser.parse(source)
    #   # => { system: { system_code: "...", body: [...] } }
    #
    # The returned tree is a parslet-shaped hash — lists of hashes with
    # symbol keys. Convert to a domain object via Interscript::Isc::DocumentBuilder.
    class Parser < Parslet::Parser
      include Grammar::Core

      root :isc_source

      def self.parse(source, filename: nil)
        new.parse_with_callbacks(source, filename: filename)
      end

      def parse_with_callbacks(source, filename: nil)
        tree = parse(source)
        tree
      rescue Parslet::ParseFailed => e
        raise ParseError.new(e.message, filename: filename, source: source, cause: e)
      end
    end

    class ParseError < StandardError
      attr_reader :filename, :source

      def initialize(message, filename:, source:, cause: nil)
        @filename = filename
        @source = source
        @cause = cause
        loc = filename ? "#{filename}: " : ""
        super("#{loc}#{message}")
      end
    end
  end
end
