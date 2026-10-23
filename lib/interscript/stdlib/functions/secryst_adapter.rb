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

        # The 126e8e1 split lost this body but kept the call — an ML
        # funcall without a provisioned model crashed with an accidental
        # NoMethodError instead of a named provisioning error (A4).
        def require_secryst!
          require "interscript/ml/translator"
        rescue LoadError => e
          raise LoadError,
                "the secryst funcall requires Interscript::ML — " \
                "loading failed: #{e.message}"
        end

        def build_translator(model_key)
          Interscript.secryst_index_locations.each do |remote|
            Interscript::ML::Provisioning.add_remote(remote)
          end
          Interscript::ML::Translator.new(model_file: model_key)
        end
      end
    end
  end
end
