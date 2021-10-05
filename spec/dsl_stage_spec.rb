RSpec.describe Interscript::DSL::Stage do
  each_compiler do |compiler|
    describe compiler do
      before :example do
        $compiler = compiler
      end

      context "#sub" do
        it "handles basic substitition" do
          s = stage {
            sub "b", "e"
          }
          expect(s.("abcd")).to eq("aecd")
          expect(s.("aecd")).to eq("aecd")
          expect(s.("bbbb")).to eq("eeee")
        end

        it "handles substitution with :before" do
          s = stage {
            sub "a", "A", before: space
          }
          expect(s.("abcda abcda abada")).to eq("abcda Abcda Abada")
        end

        it "handles substitution with :not_before" do
          s = stage {
            sub "a", "A", not_before: space
          }
          expect(s.("abcda abcda abada")).to eq("AbcdA abcdA abAdA")
        end

        it "handles substitution with :after" do
          s = stage {
            sub "a", "A", after: space
          }
          expect(s.("abcda abcda abada")).to eq("abcdA abcdA abada")
        end

        it "handles substitution with :not_after" do
          s = stage {
            sub "a", "A", not_after: space
          }
          expect(s.("abcda abcda abada")).to eq("Abcda Abcda AbAdA")
        end

        it "handles substitution with :not_before and :not_after" do
          s = stage {
            sub "a", "A", not_before: space, not_after: space
          }
          expect(s.("abcda abcda abada")).to eq("Abcda abcda abAdA")
        end

        it "handles characters inside BMP" do
          s = stage {
            sub "\u1234", "\u1235"
          }
          expect(s.("\u1234")).to eq("\u1235")
        end

        it "handles characters outside BMP" do
          s = stage {
            sub "\u{12345}", "\u{12346}"
          }
          expect(s.("\u{12345}")).to eq("\u{12346}")
        end

        it "works with upcase" do
          s = stage {
            sub "a", upcase
          }
          expect(s.("a")).to eq("A")
        end
      end

      context "#parallel" do
        it "finds the longest substrings" do
          s = stage {
            parallel {
              sub "had", "B"
              sub "little", "D"
              sub "lamb", "E"
              sub "mary", "A"
              sub "a", "C"
              sub " ", "X"
            }
          }
          expect(s.("mary had a little lamb")).to eq("AXBXCXDXE")
          expect(s.("lamborghini")).to eq("Eorghini")
          expect(s.("hadahadahada")).to eq("BCBCBC")
        end

        it "works with any" do
          s = stage {
            parallel {
              sub any("abcde"), "X"
              sub any("f".."i"), "Y"
              sub any(["AB", "CD"]), "Z"
            }
          }
          expect(s.("Cameroon")).to eq("CXmXroon")
          expect(s.("ABfghiabcdCD")).to eq("ZYYYYXXXXZ")
        end

        # The old behaviour was to take the LAST one. We may reintroduce this
        # behavior in the future, but the maps will need to be rearranged.
        #
        # it "prefers the first given replacement" do
        #   s = stage {
        #     parallel {
        #       sub any("ab"), "X"
        #       sub any("ab"), "Y"
        #     }
        #   }
        #   expect(s.("abbacus")).to eq("XXXXcus")
        # end

        context "extended engine" do
          it "falls back to an extended engine when needed" do
            s = stage {
              parallel {
                sub "a", "A", not_before: space, not_after: space
                sub "b", "B", not_before: space, not_after: space
              }
            }
            expect(s.("abcda abcda abada")).to eq("ABcda aBcda aBAdA")
          end

          it "sorts arguments correctly with an extended engine" do
            s = stage {
              parallel {
                sub "aaaa", "c", not_before: "doesntmatter"
                sub "a",    "d", not_before: "doesntmatter"
                sub "aa",   "e", not_before: "doesntmatter"
                sub "aaa",  "f", not_before: "doesntmatter"
              }
            }
            expect(s.("aaaaa")).to eq("cd")
          end

          it "works with multiple replacements" do
            s = stage {
              parallel {
                sub "a", any("bc"), not_before: "doesntmatter"
                sub "d", any("ef"), not_before: "doesntmatter"
              }
            }
            expect(s.("aaaddd")).to eq("bbbeee")
          end

          it "doesn't trigger a weird off-by-one error" do
            s = stage {
              parallel {
                sub "\u064f", "u" # ُ damma
                sub "\u0650" + boundary, "-e" # ِ kasra # needed to trigger the extended engine
                sub "\u064f", any("uo") # ُ damma
                sub "\u0627", "a" # ا
                sub "\u0648", "o" # و
              }
            }

            expect(s.("\u0627")).to eq("a")
          end
        end
      end

      context "#run" do
        it "can run other stages" do
          s = document {
            stage(other) {
              sub "a", "A"
            }

            stage {
              run stage.other
            }
          }

          expect(s.("aabaa")).to eq("AAbAA")
        end

        it "can run multiple stages" do
          s = document {
            stage(one) { sub "0", "1" }
            stage(two) { sub "1", "2" }
            stage(three) { sub "2", "3" }

            stage {
              run stage.one
              run stage.two
              run stage.three
            }
          }

          expect(s.("0")).to eq("3")
        end

        it "can run stages inside other stages" do
          s = document {
            stage(one) { run stage.two }
            stage(two) { run stage.three }
            stage(three) { sub "0", "3" }

            stage {
              run stage.one
            }
          }

          expect(s.("0")).to eq("3")
        end

        it "can run remote stages" do
          document("remote-stages") {
            stage(hello) { sub "0", "3" }
          }

          s = document {
            dependency "remote-stages", as: remote
            stage { run map.remote.stage.hello }
          }

          expect(s.("0")).to eq("3")
        end

        it "can run imported remote stages" do
          document("imported-remote-stages") {
            stage(hellohello) { sub "0", "3" }
          }

          s = document {
            dependency "imported-remote-stages", import: true
            stage { run stage.hellohello }
          }

          expect(s.("0")).to eq("3")
        end

        it "can run remote stages that run remote stages" do
          document("remotest-stage") {
            stage(seven) { sub "0", "3" }
          }
          document("remote-stage-running-remote-stage") {
            dependency "remotest-stage", as: remotest
            stage(six) { run map.remotest.stage.seven }
          }

          s = document {
            dependency "remote-stage-running-remote-stage", as: remote
            stage { run map.remote.stage.six }
          }

          expect(s.("0")).to eq("3")
        end
      end

      context "items" do
        context "#any" do
          it "handles any with string" do
            s = stage {
              sub any("abc"), "X"
            }
            expect(s.("abcda abcda abada")).to eq("XXXdX XXXdX XXXdX")
          end

          it "handles any with range" do
            s = stage {
              sub any("a".."c"), "X"
            }
            expect(s.("abcda abcda abada")).to eq("XXXdX XXXdX XXXdX")
          end

          it "handles any with array" do
            s = stage {
              sub any(["a","b","c"]), "X"
            }
            expect(s.("abcda abcda abada")).to eq("XXXdX XXXdX XXXdX")
          end

          it "handles any with a complex array of anys" do
            s = stage {
              # Any of:
              sub any([
                any("a".."z"), # range a to z
                any(["A", "B", "C"]), # A, B or C
                "123" # string "123"
              ]), "X"
            }
            expect(s.("Mary had A littlë lámb")).to eq("MXXX XXX X XXXXXë XáXX")
            expect(s.("1234512345")).to eq("X45X45")
          end

          it "handles any with concatenations" do
            s = stage {
              sub any([any("ab") + any("cd"), any("AB") + any("CD")]), "X"
            }

            expect(s.("ad AD ba ca Ad Da bd BD bD")).to eq("X X ba ca Ad Da X X bD")
          end
        end

        context "#maybe" do
          it "handles maybe with string concatenated to other string" do
            s = stage {
              sub maybe("a") + "b", "X"
            }
            expect(s.("abcdb")).to eq("XcdX")
          end

          it "handles maybe with multicharacter string" do
            s = stage {
              sub "X"+maybe("abcde")+"X", "Y"
            }
            expect(s.("XabcdeX")).to eq("Y")
            expect(s.("XX")).to eq("Y")
          end
        end

        context "#capture" do
          it "captures a string and allows to reference it" do
            s = stage {
              sub capture("a"), "-"+ref(1)+"-"
            }
            expect(s.("bab")).to eq("b-a-b")
            expect(s.("baab")).to eq("b-a--a-b")
          end

          it "captures multiple strings" do
            s = stage {
              sub capture("a")+capture("b"), ref(2)+ref(1)
            }
            expect(s.("mmabmm")).to eq("mmbamm")
          end

          it "allows for any to be used inside a captured string" do
            s = stage {
              sub capture(any("abc")), "["+ref(1)+"]"
            }
            expect(s.("abcde")).to eq("[a][b][c]de")
          end

          it "allows for #ref to be used in from part" do
            s = stage {
              sub capture("a")+ref(1), "X"
            }
            expect(s.("xax")).to eq("xax")
            expect(s.("xaax")).to eq("xXx")
          end

          it "can be aliased" do
            s = document {
              aliases {
                def_alias maybe_dash, capture(any(["-", ""]))
              }
              stage {
                sub "a"+maybe_dash+"b", "X"+ref(1)+"Y"
              }
            }
            expect(s.("abca-b-cabc")).to eq("XYcX-Y-cXYc")
          end
        end

        context "concatenation" do
          it "concatenates aliases with strings both ways" do
            s = stage {
              sub line_start + "a", "X"
              sub "a" + line_end, "Y"
            }
            expect(s.("aaaaa")).to eq("XaaaY")
          end

          it "concatenates any with strings both ways" do
            s = stage {
              sub any("bc") + "a", "X"
              sub "d" + any("ef"), "Y"
            }
            expect(s.("baca||dedf")).to eq("XX||YY")
          end

          it "concatenates multiple anys" do
            s = stage {
              sub any("ab") + any("cd") + any("ef") + any("gh"), "X"
            }
            expect(s.("adeg dd ab bcfh")).to eq("X dd ab X")
          end
        end

        context "stdlib aliases" do
          it "handles boundary correctly" do
            s = stage {
              sub boundary, "|"
            }
            expect(s.("Mary had A   littlë lámb!")).to eq("|Mary| |had| |A|   |littlë| |lámb|!")
          end

          it "handles non_word_boundary correctly" do
            s = stage {
              sub non_word_boundary, "|"
            }
            expect(s.("Mary had A   littlë lámb!")).to eq("M|a|r|y h|a|d A | | l|i|t|t|l|ë l|á|m|b!|")
          end
        end

        context "local aliases" do
          it "handles local aliases correctly" do
            s = document {
              aliases {
                def_alias hello, any(["hello", "Hello", "HELLO"])
              }

              stage {
                sub hello, "Goodbye"
              }
            }
            expect(s.("Hello world")).to eq("Goodbye world")
          end
        end

        context "remote aliases" do
          document("remote-aliases") {
            aliases {
              def_alias from_name, "404"
              def_alias to_name, "500"
            }
          }

          it "handles remote aliases correctly" do
            s = document {
              dependency "remote-aliases", as: remo
              stage {
                sub map.remo.from_name, map.remo.to_name
              }
            }
            expect(s.("Error 404")).to eq("Error 500")
          end

          it "handles imported remote aliases correctly" do
            s = document {
              dependency "remote-aliases", import: true
              stage {
                sub from_name, to_name
              }
            }
            expect(s.("Route 404")).to eq("Route 500")
          end
        end

        context "multiple versions of replacement" do
          it "works with any" do
            s = stage {
              sub any("a"), any("XY")
              sub any("b"), any(["X", "Y"])
            }
            expect(s.("abbacus")).to eq("XXXXcus")
          end

          it "works with any + concatenation" do
            s = stage {
              sub any("ab"), "["+any("XY")+"]"
            }
            expect(s.("abbacus")).to eq("[X][X][X][X]cus")
          end

          it "works with any(any())" do
            s = stage {
              sub any("ab"), any([any("XY"), "Z"])
            }
            expect(s.("abbacus")).to eq("XXXXcus")
          end

          it "works with references" do
            s = stage {
              sub capture(any("a".."s")), any(["["+ref(1)+"]", "other"])
            }
            expect(s.("abbacus")).to eq("[a][b][b][a][c]u[s]")
          end

          it "works with stdlib aliases" do
            s = stage {
              sub any("ab"), any([none, space])
            }
            expect(s.("abbacus")).to eq("cus")
          end

          it "works with parallel" do
            s = stage {
              parallel {
                sub any("ab"), any(["XA", "YB"])
                sub "d", any(["88", "99", "00"])
                sub any("ef"), any("ZT")
              }
            }
            expect(s.("abcdefgh")).to eq("XAXAc88ZZgh")
          end
        end
      end

      context "stdlib calls" do
        it "handles a title case stdlib call correctly" do
          s = stage {
            title_case
          }
          expect(s.("hello world hello hello")).to eq("Hello World Hello Hello")
        end

        it "handles a title case stdlib call with :word_separator correctly" do
          s = stage {
            title_case word_separator: ""
          }
          expect(s.("hello world hello hello")).to eq("Hello world hello hello")
          expect(s.("hello world\nhello hello")).to eq("Hello world\nHello hello")
        end

        it "handles a separate stdlib call correctly" do
          s = stage {
            separate
          }
          expect(s.("こんいちは")).to eq("こ ん い ち は")
        end

        it "handles a separate stdlib call with :separator correctly" do
          s = stage {
            separate separator: "|"
          }
          expect(s.("こんいちは")).to eq("こ|ん|い|ち|は")
        end

        it "handles a compose call correctly" do
          s = stage {
            compose
          }
          expect(s.("ᄆ"+"ᅮ")).to eq("무")
        end

        it "handles a decompose call correctly" do
          s = stage {
            decompose
          }
          expect(s.("무")).to eq("ᄆ"+"ᅮ")
        end
      end
    end
  end
end
