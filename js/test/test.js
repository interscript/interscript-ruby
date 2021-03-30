var assert = require('assert');
var Interscript = require('../src/stdlib');

describe('interscript-js', function() {
  it('can transcribe', async function () {
    var src = "Антон";
    await Interscript.load_map('bgnpcgn-ukr-Cyrl-Latn-2019');
    var dest = Interscript.transcribe('bgnpcgn-ukr-Cyrl-Latn-2019', src);
    assert.strictEqual(dest, 'Anton');
  });
});
