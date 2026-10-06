# frozen_string_literal: true

# Neural cross-runtime parity: run a real artifact against the shared
# golden set (interscript-models/golden/*.jsonl) and require
# byte-identical output. Gated behind SECRYST_E2E_ZIP + SECRYST_GOLDEN
# (same contract as the Python and TypeScript runners).

RSpec.describe Interscript::ML::IMF do
  # Quantized (int8) graphs are NOT byte-portable across onnxruntime
  # builds: near-tied logits can flip argmax. Measured on
  # ara-diac-plane-1.0 (py reference vs this runtime): 3/50 rows with
  # 1-2 char diffs over 600-1000-char rows - numeric, not logic. The
  # parity contract for quantized models is therefore per-row char
  # agreement >= 99.5% and corpus agreement >= 99.9%. Deterministic
  # graphs (fp32 fixtures, maps) remain byte-exact via the plain path.
  describe "golden set e2e (cross-runtime parity)" do
    it "matches the reference within the quantized tolerance (or byte-exactly for fp32)" do
      zip = ENV["SECRYST_E2E_ZIP"]
      golden = ENV["SECRYST_GOLDEN"]
      skip "set SECRYST_E2E_ZIP and SECRYST_GOLDEN" if zip.nil? || golden.nil?

      plane = ENV["SECRYST_E2E_PLANE"] == "1"
      require "json"
      rows = File.readlines(golden, chomp: true).reject(&:empty?).map { |l| JSON.parse(l) }
      model =
        if plane
          Interscript::ML::PlaneModel.from_zip(File.binread(zip))
        else
          Interscript::ML::Translator.new(model_file: zip)
        end

      total_chars = 0
      total_diffs = 0
      rows.each do |row|
        out = plane ? model.translate(row["input"]) : model.translate(row["input"], max_seq_length: 128)
        total_chars += row["output"].length
        next if out == row["output"]

        exp = row["output"].chars
        got = out.chars
        d = (0...[exp.length, got.length].min).count { |j| exp[j] != got[j] }
        total_diffs += d
        expect(d.to_f / exp.length).to be < 0.005, row["input"][0, 60]
      end
      expect(total_diffs.to_f / total_chars).to be < 0.001
    end
  end
end
