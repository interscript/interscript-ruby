# frozen_string_literal: true

# The neural layer: IMF v1 artifact runtime + index provisioning for
# byte-level ByT5 models, ported from the secryst crystal (1.1.1) into
# interscript proper. Runtime dependencies rubyzip and onnxruntime are
# OPTIONAL: they load lazily with a helpful error when absent.
#
#   Interscript::ML::Translator.new(model_file: "khm-latn-1.0")
#     .translate("ភាសា")
module Interscript::ML
  autoload :IMF, "interscript/ml/imf"
  autoload :Provisioning, "interscript/ml/provisioning"
  autoload :Translator, "interscript/ml/translator"
  autoload :Model, "interscript/ml/model"
  autoload :Vocab, "interscript/ml/vocab"
  autoload :Byt5Onnx, "interscript/ml/byt5_onnx"

  # Expected to be loaded before IMF/Byt5Onnx entry points.
  def self.require_optional!(gem_name, feature: gem_name)
    require feature
  rescue LoadError => e
    raise Interscript::ExternalUtilError,
      "the neural layer needs the #{gem_name} gem: gem install #{gem_name} (or use a bundle including it)"
  end
end
