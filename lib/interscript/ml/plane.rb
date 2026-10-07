# frozen_string_literal: true

require 'tmpdir'
require 'json'

module Interscript
  module ML
    # Plane-factorized runtime (kind=plane artifacts): one ONNX graph
    # maps (input_ids, plane_ids) -> per-position class logits over the
    # diacritic classes; decoding is K mask-predict passes feeding the
    # argmax plane back. Per-character class = majority vote of the
    # char's byte-token predictions; render splices one mark after each
    # base character. Token ids follow the canonical ByT5 table (byte+3,
    # trailing EOS) — see Interscript::ML::IMF.
    class PlaneModel
      attr_reader :classes, :k_passes

      def initialize(graph:, classes:, k_passes: 2)
        Interscript::ML.require_optional!('onnxruntime')
        @classes = classes.freeze
        @n_classes = classes.length
        @mask_id = @n_classes
        @k_passes = k_passes
        # a character is a diacritic iff it occurs inside some class the
        # artifact knows — no per-language mark tables needed
        @mark_chars = classes.flat_map { |c| c.chars }.reject(&:empty?).uniq.freeze
        @class_to_id = classes.each_with_index.to_h.freeze
        # the onnxruntime gem loads from paths, not bytes (as byt5_onnx):
        # verified bytes go to a tmpfile owned by this instance
        @graph_tmpdir = Dir.mktmpdir('isx-plane')
        path = File.join(@graph_tmpdir, 'plane.onnx')
        File.binwrite(path, graph)
        @sess = OnnxRuntime::Model.new(path)
      end

      # Split text into (skeleton, per-base classes). Marks FOLLOW their
      # base letter; leading marks bind to a "\x00" anchor (render drops
      # it). Cluster order is preserved as written — render-exactness
      # beats normalization (the Hebrew canon lesson).
      def split_planes(text)
        skeleton = []
        classes = []
        current = []
        close = lambda do
          next if current.empty?

          if skeleton.empty?
            skeleton << "\x00"
            classes << current.join
          else
            classes[-1] = classes[-1] + current.join
          end
          current = []
        end
        text.each_char do |ch|
          if @mark_chars.include?(ch)
            current << ch
          else
            close.call
            skeleton << ch
            classes << ''
          end
        end
        close.call
        [skeleton.join, classes]
      end

      def translate(text, preserve_diacritics: false)
        return translate_plain(text) unless preserve_diacritics

        skeleton, char_classes = split_planes(text)
        tok_preds = decode_pinned(skeleton, char_classes)
        pos = 0
        final = char_classes.each_with_index.map do |user_cls, i|
          ch = skeleton[i]
          n = ch.bytesize
          cls = if user_cls.empty?
                  votes = tok_preds[pos, n] || []
                  cid = votes.tally.max_by { |_, c| c }&.first || @n_classes
                  cid < @n_classes ? @classes[cid] : ''
                else
                  user_cls # user diacritics round-trip byte-exactly
                end
          pos += n
          cls
        end
        out = +""
        skeleton.each_char.with_index do |ch, i|
          out << (ch == "\x00" ? final[i] : ch + final[i])
        end
        out
      end

      private

      def translate_plain(text)
        ids = IMF.encode(text)[0..-2] # strip EOS: one token per byte
        preds = k_pass_decode(ids, Array.new(ids.length, @mask_id))
        pos = 0
        char_preds = text.each_char.map do |ch|
          nbytes = ch.bytesize
          votes = preds[pos, nbytes] || []
          cid = votes.tally.max_by { |_, c| c }&.first || @n_classes
          pos += nbytes
          cid < @n_classes ? @classes[cid] : ''
        end
        PlaneModel.render_plane(text, char_preds)
      end

      def k_pass_decode(ids, plane0)
        plane = plane0
        preds = nil
        @k_passes.times do
          logits = @sess.predict({ 'input_ids' => [ids], 'plane_ids' => [plane] })['class_logits'][0]
          preds = logits.each_with_index.map { |row, i| row.index(row.max) }
          plane = preds
        end
        preds
      end

      # K-pass decode with user classes pinned: known classes are
      # conditioned AND never overwritten; unknown non-empty clusters
      # stay masked during decode but are restored at render.
      def decode_pinned(skeleton, char_classes)
        ids = IMF.encode(skeleton)[0..-2]
        per_token_pin = []
        skeleton.each_char.with_index do |ch, i|
          cls = char_classes[i]
          pid = @class_to_id.fetch(cls, @mask_id)
          ch.bytesize.times { per_token_pin << pid }
        end
        plane0 = per_token_pin.map { |p| p == @mask_id ? @mask_id : p }
        k_pass_decode(ids, plane0)
      end

      def self.render_plane(skeleton, char_classes)
        skeleton.each_char.with_index.map do |ch, i|
          ch + char_classes[i].to_s
        end.join
      end

      # The zip contract: metadata.yaml (kind=plane, k_passes, member
      # sha256s) + plane.onnx + classes.json, every member sha-verified
      # before the session is created.
      def self.from_zip(data)
        require 'zip'
        zf = Zip::File.open_buffer(data)
        names = zf.entries.map(&:name)
        meta = YAML.safe_load(zf.read('metadata.yaml'), permitted_classes: [], aliases: false)
        raise IMF::FormatError, "plane zip: kind=#{meta['kind'].inspect}, expected 'plane'" if meta['kind'] != 'plane'

        members = meta['members'] || {}
        plane_graph = nil
        classes_bytes = nil
        %w[plane.onnx classes.json].each do |member|
          raise IMF::FormatError, "plane zip: #{member} missing" unless names.include?(member)

          bytes = zf.read(member)
          want = members[member]
          raise IMF::FormatError, "plane zip: #{member} has no sha256 in metadata" if want.nil?
          got = Digest::SHA256.hexdigest(bytes)
          raise IMF::FormatError, "plane zip: #{member} sha256 mismatch (#{got})" if want != got

          plane_graph = bytes if member == 'plane.onnx'
          classes_bytes = bytes if member == 'classes.json'
        end
        classes = JSON.parse(classes_bytes)
        new(graph: plane_graph, classes: classes, k_passes: meta.fetch('k_passes', 2))
      ensure
        zf&.close
      end
    end

    module_function

    def render_plane(skeleton, char_classes)
      PlaneModel.render_plane(skeleton, char_classes)
    end
  end
end
