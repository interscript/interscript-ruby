module Interscript::ML
  # Dispatching translator: byte-level ByT5 models (name: byt5 in
  # metadata.yaml) translate themselves; legacy char-vocab ONNX zips use
  # the original greedy loop.
  class Translator
    attr_accessor :model

    def initialize(model_file:)
      @device = 'cpu'
      @model = Model.from_file(model_file)
    end

    def translate(phrase, max_seq_length: 100)
      return @model.translate(phrase, max_seq_length: max_seq_length) if @model.is_a?(Byt5Onnx)

      Interscript::ML.require_optional!("numo-narray", feature: "numo/narray")
      input = ['<sos>'] + phrase.chars + ['<eos>']
      input = Numo::NArray[input.map { |i| @model.input_vocab.stoi[i] }].transpose
      output = Numo::NArray[[@model.target_vocab.stoi['<sos>']]]
      src_key_padding_mask = input.transpose.eq(1)

      max_seq_length.times do |i|
        tgt_key_padding_mask = output.transpose.eq(1)
        tgt_mask = Numo::DFloat.ones(i + 1, i + 1).triu.transpose.eq(0)
        prediction = @model.argmax(input, output.dup,
          tgt_mask: tgt_mask,
          src_key_padding_mask: src_key_padding_mask,
          tgt_key_padding_mask: tgt_key_padding_mask,
          memory_key_padding_mask: src_key_padding_mask)
        break if @model.target_vocab.itos[prediction[i]] == '<eos>'

        output = Numo::NArray.concatenate([output, Numo::NArray[[prediction[i]]]])
      end

      output[1..-1].to_a.flatten.map { |i| @model.target_vocab.itos[i] }.join('')
    end
  end
end
