require "interscript/ml/imf"
require "interscript/ml/byt5_onnx"

module Interscript
  # Interscript::Ml — run the IMF v1 models published by
  # interscript-models (index, sha256-verified downloads, byte-level
  # ByT5 inference) from the interscript gem.
  #
  #   require "interscript/ml"
  #   Interscript::Ml.translate("urd-diac-base-1.0", "کلیدهای پرکینزمانند")
  #
  # Optional runtime dependencies: onnxruntime, rubyzip, numo-narray
  # (kv-mode models). A missing gem raises a LoadError naming it.
  module Ml
    DEFAULT_INDEX_URL = IMF::DEFAULT_INDEX_URL

    class << self
      # Resolve + load + translate in one call. The artifact is cached
      # (and re-verified) under Interscript::Ml::IMF.cache_dir.
      def translate(model_id, text, index_url: nil, max_seq_length: 256)
        model = load(model_id, index_url: index_url)
        model.translate(text, max_seq_length: max_seq_length)
      end

      def load(model_id, index_url: nil)
        path = IMF.resolve(model_id, index_url: index_url)
        Byt5Onnx.new(path)
      end
    end
  end
end
