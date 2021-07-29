RSpec.describe "composability" do
  it "can depend on reversed maps" do
    a = document("part-1-One-Two") {
      stage {
        sub "a", "b"
      }
    }

    b = document("part-2-One-Two") {
      stage {
        sub "c", "d"
      }
    }

    c = document("composed") {
      dependency "part-1-Two-One", as: twoone
      dependency "part-2-One-Two", as: onetwo

      stage {
        run map.twoone.stage.main
        run map.onetwo.stage.main
      }
    }

    expect(c.("abcd")).to eq("aadd")
  end

  it "can seamlessly compose two maps" do
    a = document("part1") {
      stage {
        sub "a", "b"
      }
    }
    b = document("part2") {
      stage {
        sub "c", "d"
      }
    }

    c = document("composed2") {
      dependency "part1|part2", as: composed

      stage {
        run map.composed.stage.main
      }
    }

    expect(c.("abcd")).to eq("bbdd")
  end
end