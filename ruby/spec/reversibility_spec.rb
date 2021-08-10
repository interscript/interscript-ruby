RSpec.describe "Reversibility" do
  describe "stage tests" do
    it "reverses a basic stage" do
      a = stage {
        sub "a", "b"
      }

      b = stage {
        sub "b", "a"
      }

      expect(a.reverse).to eq(b)
    end

    it "reverses a multirule stage" do
      a = stage {
        sub "a", "b"
        sub "c", "d"
      }

      b = stage {
        sub "d", "c"
        sub "b", "a"
      }

      expect(a.reverse).to eq(b)
    end

    it "reverses a multirule stage and preserves before/after" do
      a = stage {
        sub "a", "b", before: "c"
        sub "c", "d", after: "d"
      }

      b = stage {
        sub "d", "c", after: "d"
        sub "b", "a", before: "c" 
      }

      expect(a.reverse).to eq(b)
    end

    it "reverses a multirule stage and preserves not before/not after" do
      a = stage {
        sub "a", "b", not_before: "c"
        sub "c", "d", not_after: "d"
      }

      b = stage {
        sub "d", "c", not_after: "d"
        sub "b", "a", not_before: "c" 
      }

      expect(a.reverse).to eq(b)
    end

    it "reverses a parallel stage" do
      a = stage {
        parallel {
          sub "a", "b"
          sub "c", "d"
          sub "e", "f"
        }
      }

      b = stage {
        parallel {
          sub "f", "e"
          sub "d", "c"
          sub "b", "a"
        }
      }

      expect(a.reverse).to eq(b)
    end

    it "reverses a parallel stage and other rules if present" do
      a = stage {
        sub "X", "Y"
        parallel {
          sub "a", "b"
          sub "c", "d"
          sub "e", "f"
        }
      }

      b = stage {
        parallel {
          sub "f", "e"
          sub "d", "c"
          sub "b", "a"
        }
        sub "Y", "X"
      }

      expect(a.reverse).to eq(b)
    end

    it "reverses with reverse_run correctly" do
      a = stage {
        sub "X", "Y", reverse_run: true
        parallel {
          sub "a", "b", reverse_run: false
          sub "c", "d"
          sub "e", "f"
        }
      }

      b = stage {
        parallel {
          sub "f", "e"
          sub "d", "c"
          sub "b", "a", reverse_run: true
        }
        sub "Y", "X", reverse_run: false
      }

      expect(a.reverse).to eq(b)
    end
  end

  describe "item tests" do
    it "transforms boundary" do
      a = stage {
        sub "a"+boundary, "b"
      }

      b = stage {
        sub "b"+boundary, "a"
      }

      expect(a.reverse).to eq(b)
    end

    it "transforms captures and references" do
      a = stage {
        sub capture("a"), ref(1)+"b"
      }

      b = stage {
        sub capture("a")+"b", ref(1)
      }

      expect(a.reverse).to eq(b)
    end

    it "doesn't transform any" do
      a = stage {
        sub any("ab"), any("bc")
      }

      b = stage {
        sub any("bc"), any("ab")
      }

      expect(a.reverse).to eq(b)
    end
  end

  describe "document transformations" do
    it "transforms document name correctly when it transforms between different character sets" do
      a = document("var-kor-Kore-Hang-test") { }

      expect(a.reverse.name).to eq("var-kor-Hang-Kore-test")
    end

    it "transforms document name correctly when it transforms between the same character sets" do
      a = document("var-swe-Latn-Latn-test") { }

      expect(a.reverse.name).to eq("var-swe-Latn-Latn-test-reverse")
    end

    it "transforms input and output charset in metadata correctly" do
      a = document {}
      a.metadata = Interscript::Node::MetaData.new
      a.metadata[:source_script] = "Hani"
      a.metadata[:destination_script] = "Latn"

      b = a.reverse
      expect(b.metadata[:source_script]).to eq("Latn")
      expect(b.metadata[:destination_script]).to eq("Hani")
    end

    it "transforms tests" do
      a = document {
        tests {
          test "a", "b"
          test "c", "d"
        }
      }

      b = document {
        tests {
          test "b", "a"
          test "d", "c"
        }
      }

      expect(a.reverse).to eq(b)
    end
  end

  describe "reverse_run" do
    it "transliterates correctly with reverse_run: nil" do
      a = stage {
        sub "a", "b"
      }
      b = a.reverse

      expect(a.("ab")).to eq("bb")
      expect(b.("ab")).to eq("aa")
    end

    it "transliterates correctly with reverse_run: true" do
      a = stage {
        sub "a", "b", reverse_run: true
      }
      b = a.reverse

      expect(a.("ab")).to eq("ab")
      expect(b.("ab")).to eq("aa")
    end

    it "transliterates correctly with reverse_run: false" do
      a = stage {
        sub "a", "b", reverse_run: false
      }
      b = a.reverse

      expect(a.("ab")).to eq("bb")
      expect(b.("ab")).to eq("ab")
    end

    it "transliterates correctly with reverse_run and parallel" do
      a = stage {
        parallel {
          sub "a", "b", reverse_run: true
          sub "c", "d", reverse_run: false
        }
      }
      b = a.reverse

      expect(a.("abcd")).to eq("abdd")
      expect(b.("abcd")).to eq("aacd")
    end
  end

  describe "multistage" do
    it "correctly reverses multistage documents" do
      a = document("multistage-reversibility") {
        stage {
          sub "a", "b"
          sub "c", "d"
          run stage.second
        }

        stage(:second) {
          sub "e", "f"
        }
      }
      b = a.reverse

      expect(a.("abcdef")).to eq("bbddff")
      expect(b.("abcdef")).to eq("aaccee")
    end

    it "correctly reverses multistage documents with dont_reverse" do
      a = document("multistage-reversibility-dr") {
        stage {
          sub "a", "b"
          sub "c", "d"
          run stage.second
        }

        stage(:second, dont_reverse: true) {
          sub "e", "f"
        }
      }
      b = a.reverse

      expect(a.("abcdef")).to eq("bbddff")
      expect(b.("abcdef")).to eq("aaccff")
    end
  end
end