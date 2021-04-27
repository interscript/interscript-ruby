var assert = require('assert');
var Interscript = require('../src/stdlib');

async function test_translit(map, src, dest) {
  await Interscript.load_map(map);
  var value = Interscript.transliterate(map, src);
  assert.strictEqual(value, dest);
}

describe('interscript-js', function() {
  it('contains a list of available maps - at first 0, but later a correct value', async function () {
    var mapcount = Object.keys(Interscript.maps).length;
    assert.ok(mapcount == 0);
    await Interscript.load_map_list();
    mapcount = Object.keys(Interscript.maps).length;
    assert.ok(mapcount > 100);
  });

  it('can transliterate', async function () {
    await test_translit('bgnpcgn-ukr-Cyrl-Latn-2019', 'Антон', 'Anton');
  });

  it('can transliterate maps requiring libraries', async function() {
    await test_translit('bgnpcgn-deu-Latn-Latn-2000', 'Tschüß!', 'Tschueß!');
  });
});
