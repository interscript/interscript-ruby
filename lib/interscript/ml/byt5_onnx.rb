require 'tmpdir'

module Interscript::ML
  # Byte-level seq2seq (ByT5 family) inference over ONNX sessions from an
  # IMF v1 model zip: sha256-verified graphs, greedy KV-cache decode when
  # the zip ships decoder-kv.onnx (default), plain full-recompute
  # fallback otherwise. Tokenization is the canonical ByT5 table
  # (byte b -> id b+3, trailing EOS) — see Interscript::ML::IMF.
  class Byt5Onnx
    def initialize(zip_path)
      Interscript::ML.require_optional!("onnxruntime")
      @manifest = IMF.manifest(zip_path)
      graphs = IMF.verify_and_read(zip_path)
      @tmpdir = Dir.mktmpdir('secryst-imf')
      @encoder = build_session(graphs, 'encoder.onnx')
      @kv = @manifest['decoder'] == 'kv' && graphs.key?('decoder-kv.onnx')
      @decoder = build_session(graphs, @kv ? 'decoder-kv.onnx' : 'decoder.onnx')
      @pasts = @kv ? zero_pasts : {}
    end

    def translate(text, max_seq_length: 256)
      ids = IMF.encode(text)
      return '' if ids.length == 1 # only the trailing EOS: empty input

      hidden = @encoder.predict({ input_ids: [ids] })['last_hidden_state']
      tokens = @kv ? greedy_kv(hidden, max_seq_length) : greedy_plain(hidden, max_seq_length)
      IMF.decode(tokens)
    end

    def id
      @manifest['id']
    end

    private

    # The onnxruntime gem loads from paths, not bytes: verified bytes go
    # to a private tmpdir.
    def build_session(graphs, name)
      path = File.join(@tmpdir, name)
      File.binwrite(path, graphs.fetch(name))
      OnnxRuntime::Model.new(path)
    end

    def zero_pasts
      @decoder.inputs.each_with_object({}) do |meta, pasts|
        next unless meta[:name].start_with?('past_')
        shape = meta[:shape] # [batch, heads, past_seq, d_kv]; dynamic dims are Strings
        heads = shape[1].is_a?(Integer) ? shape[1] : 4
        d_kv = shape[3].is_a?(Integer) ? shape[3] : 8
        # Numo carries the explicit [1, heads, 0, d_kv] shape through;
        # nested Ruby arrays cannot express a zero-length dim.
        pasts[meta[:name]] = Numo::DFloat.zeros(1, heads, 0, d_kv)
      end
    end

    def argmax(row)
      best = 0
      best_val = -Float::INFINITY
      row.each_with_index do |value, index|
        if value > best_val
          best_val = value
          best = index
        end
      end
      best
    end

    def greedy_kv(hidden, max_seq_length)
      pasts = @pasts.dup
      current = [IMF::PAD_ID]
      generated = []
      max_seq_length.times do
        results = @decoder.predict(
          { input_ids: [current], encoder_hidden_states: hidden }.merge(pasts)
        )
        token = argmax(results['logits'].first.last)
        break if token == IMF::EOS_ID

        generated << token
        pasts = pasts.keys.to_h { |name| [name, results[name.sub('past_', 'present_')]] }
        current = [token]
      end
      generated
    end

    def greedy_plain(hidden, max_seq_length)
      decoder_ids = [IMF::PAD_ID]
      generated = []
      max_seq_length.times do
        logits = @decoder.predict(
          { input_ids: [decoder_ids], encoder_hidden_states: hidden }
        )['logits']
        token = argmax(logits.first.last)
        break if token == IMF::EOS_ID

        generated << token
        decoder_ids = decoder_ids + [token]
      end
      generated
    end
  end
end
