var assert = require("assert");
var Interscript = require("../src/stdlib");

describe("interscript-js", function () {
  it("contains a list of available maps - at first 0, but later a correct value", async function () {
    var mapcount = Object.keys(Interscript.maps).length;
    assert.ok(mapcount == 0);
    await Interscript.load_map_list();
    mapcount = Object.keys(Interscript.maps).length;
    assert.ok(mapcount > 100);
  });

  it("can transliterate", async function () {
    var src = "Антон";
    await Interscript.load_map("bgnpcgn-ukr-Cyrl-Latn-2019");
    var dest = Interscript.transliterate("bgnpcgn-ukr-Cyrl-Latn-2019", src);
    assert.strictEqual(dest, "Anton");
  });
  it("check existence of map", async function () {
    const map = "acadsin-zho-Hani-Latn-2002";
    await Interscript.load_map(map);
    const dest = Interscript.map_exist(map);
    assert.strictEqual(dest, true);
  });
  it("should return false for non-available map", async function () {
    const map = "alalc-per-Arab-Latn-2012";
    const dest = Interscript.map_exist(map);
    assert.strictEqual(dest, false);
  });
});
