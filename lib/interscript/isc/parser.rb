# frozen_string_literal: true

require "parsanol"

module Interscript
  module Isc
    # Entry point for parsing ISC source files.
    #
    #   tree = Interscript::Isc::Parser.parse(source)
    #   # => { system: { system_code: "...", body: [...] } }
    #
    # The returned tree is a parslet-shaped hash — lists of hashes with
    # symbol keys. Convert to a domain object via Interscript::Isc::DocumentBuilder.
    class Parser < Parsanol::Parser
      include Grammar::Core

      root :isc_source

      # The compiled grammar, shipped alongside the .parg source; the
      # runtime parses through it when parsanol carries PARG (>= 1.3.61)
      # and falls back to the Ruby-DSL grammar otherwise. Trees are
      # byte-identical by the corpus gate in the parg_diff spec.
      ARTIFACT_PATH = File.expand_path("grammar/isc.artifact.json", __dir__)

      class ArtifactUnavailable < StandardError; end

      class << self
        def parse(source, filename: nil)
          parse_with_callbacks(source, filename: filename)
        end

        def parse_with_callbacks(source, filename: nil)
          tree = begin
            parse_with_artifact(source)
          rescue ArtifactUnavailable
            parse_with_dsl(source)
          end
          Normalizer.normalize(tree)
        rescue Parsanol::ParseFailed => e
          raise ParseError.new(e.message, filename: filename, source: source, cause: e)
        end

        def parse_with_artifact(source)
          artifact.parse("isc", source)
        end

        def parse_with_dsl(source)
          new.parse(source)
        end

        def artifact
          @artifact ||= begin
            require "parsanol/parg"
            Parsanol::PARG::Artifact.load(ARTIFACT_PATH)
          rescue LoadError, StandardError => e
            raise ArtifactUnavailable, "parg artifact unavailable: #{e.class}: #{e.message}"
          end
        end

        def reset_artifact
          @artifact = nil
        end
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
