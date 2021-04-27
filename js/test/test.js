var assert = require('assert');
var Interscript = require('../src/stdlib');

describe('interscript-js', function() {
  it('contains a list of available maps - at first 0, but later a correct value', async function () {
    var mapcount = Object.keys(Interscript.maps).length;
    assert.ok(mapcount == 0);
    await Interscript.load_map_list();
    mapcount = Object.keys(Interscript.maps).length;
    assert.ok(mapcount > 100);
  });

  it('can transliterate', async function () {
    var src = "Антон";
    await Interscript.load_map('bgnpcgn-ukr-Cyrl-Latn-2019');
    var dest = Interscript.transliterate('bgnpcgn-ukr-Cyrl-Latn-2019', src);
    assert.strictEqual(dest, 'Anton');
  });
});
