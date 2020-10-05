var assert = require('assert');
var Opal = require('../vendor/assets/javascripts/interscript.js');
var fs = require('fs');

Object.keys(InterscriptMaps).forEach(function(key) {
	var json = fs.readFileSync("vendor/assets/maps/" + key + ".json");
	Opal.Opal.Interscript.$load_map_json(key, json);
	var map = JSON.parse(InterscriptMaps[key]);
	describe(key+' system', function () {
		this.timeout(10000);

		if (map.map.transcription || (map.chain && map.chain.indexOf("var-tha-Thai-Thai-phonemic") !== -1)) {
			// We don't support external processes on the JS side, so
			// * royin-tha-Thai-Latn-1999
			// * var-tha-Thai-Thai-phonemic
			// * royin-tha-Thai-Latn-1939-generic
			// * royin-tha-Thai-Latn-1968
			// * royin-tha-Thai-Latn-1999-chained
			// are unsupported

			return;
		}

		map.tests && map.tests.forEach(function(test) {

      if (test['source'] === null || test['expected'] === null)
        return;

			it('test for ' + JSON.stringify(test), function () {
				var result = Opal.Opal.Interscript.$transliterate(key, test['source']);
				var expected = test['expected'] && test['expected'].normalize();
				if (result !== expected) console.log(result);
				assert.strictEqual(result, expected);
				//assert.equal(!!result || result === "", true);
			});
		});
	});
});
