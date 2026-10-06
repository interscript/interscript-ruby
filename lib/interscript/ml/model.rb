module Interscript::ML
  class Model
    attr_accessor :model, :input_vocab, :target_vocab

    def self.from_file(model_file)
      # A models.yaml model id resolves (download -> verify -> cache)
      # through the same contract as the Python/TS runtimes.
      model_file = IMF.resolve(model_file) unless model_file.to_s.end_with?('.zip') || File.file?(model_file.to_s)
      model_file = Provisioning.locate(model_file)

      Zip::File.open(model_file) do |zip_file|
        metadata = zip_file.glob('metadata.yaml').first
        metadata = YAML.safe_load(metadata.get_input_stream.read) if metadata

        # IMF v1: the Interscript Model Format zip.
        return Byt5Onnx.new(model_file) if metadata && metadata['format'] == 'imf-v1'

        name = metadata && metadata['name']

        # Modern byte-level seq2seq (ByT5 family): encoder.onnx + decoder.onnx.
        return Byt5Onnx.new(model_file) if name == 'byt5'

        # Legacy single-file ONNX transformer zips (vocabs.yaml based).
        vocabs = zip_file.glob('vocabs.yaml').first
        raise 'vocabs.yaml is missing in model zip!' unless vocabs
        vocabs = YAML.safe_load(vocabs.get_input_stream.read)
        input_vocab = Vocab.new(vocabs['input'], specials: [])
        target_vocab = Vocab.new(vocabs['target'], specials: [])

        onnx = zip_file.glob('*.onnx').first
        raise 'onnx model file is missing in model zip!' unless onnx
        Onnx.new(onnx.get_input_stream.read, input_vocab, target_vocab)
      end
    end

    class Onnx < Model
      def initialize(model_path_or_bytes, input_vocab, target_vocab)
        @model = OnnxRuntime::Model.new(model_path_or_bytes)
        @input_vocab = input_vocab
        @target_vocab = target_vocab
      end

      def call(input, output, opts)
        @model.predict({ src: input, tgt: output }.merge(opts))['output']
      end

      def argmax(*args)
        self.call(*args).map { |i| i.flatten.each_with_index.max[1] }
      end
    end
  end
end
