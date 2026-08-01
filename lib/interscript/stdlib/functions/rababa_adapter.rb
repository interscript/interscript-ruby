class Interscript::Stdlib
  module Functions
    class RababaAdapter
      @rababa_diacritizer = nil
      @mutex = Mutex.new

      class << self
        def call(output, config:)
          diacritizer = diacritizer_for(config)
          diacritizer.diacritize_text(output)
        end

        def reverse(output, config: nil)
          # The legacy rababa reverse path strips harakat directly. It does
          # not need the model loaded — keep it dependency-free so maps
          # that only call `rababa_reverse` work without Rababa installed.
          output.gsub(/[ًٌٍَُِّْ]/, "")
        end

        def reset_cache
          @mutex.synchronize { @rababa_diacritizer = nil }
        end

        private

        def diacritizer_for(config_key)
          require_rababa!
          @mutex.synchronize do
            @rababa_diacritizer ||= build_diacritizer(config_key)
          end
        end

        def build_diacritizer(config_key)
          config_value = Interscript.rababa_configs.fetch(config_key) do
            raise Interscript::ExternalUtilError,
              "No rababa config registered under '#{config_key}'"
          end
          model_uri = config_value["model"]
          rababa_config = config_value["config"]
          model_path = Interscript.rababa_provision(config_key, model_uri)
          Rababa::Diacritizer.new(model_path, rababa_config)
        end

        def require_rababa!
          return if defined?(Rababa)
          begin
            require "rababa"
          rescue LoadError
            raise Interscript::ExternalUtilError,
              "Rababa is not loaded. Please read docs/Usage_with_Rababa.adoc"
          end
        end
      end
    end
  end
end
