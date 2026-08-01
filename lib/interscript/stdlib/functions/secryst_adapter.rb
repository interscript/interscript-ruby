class Interscript::Stdlib
  module Functions
    class SecrystAdapter
      @translators = {}
      @mutex = Mutex.new

      class << self
        def call(output, model:)
          translator = translator_for(model)
          output.split("\n").map(&:chomp).map { |line| translator.translate(line) }.join("\n")
        end

        def reset_cache
          @mutex.synchronize { @translators.clear }
        end

        private

        def translator_for(model_key)
          require_secryst!
          @mutex.synchronize do
            @translators[model_key] ||= build_translator(model_key)
          end
        end

        def build_translator(model_key)
          Interscript.secryst_index_locations.each do |remote|
            Secryst::Provisioning.add_remote(remote)
          end
          Secryst::Translator.new(model_file: model_key)
        end

        def require_secryst!
          return if defined?(Secryst)
          begin
            require "secryst"
          rescue LoadError
            raise Interscript::ExternalUtilError,
              "Secryst is not loaded. Please read docs/Usage_with_Secryst.adoc"
          end
        end
      end
    end
  end
end
