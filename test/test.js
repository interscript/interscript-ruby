var assert = require('assert');
var Opal = require('../vendor/assets/javascripts/interscript.opt.js');
var fs = require('fs');

// Let's cache the work that is done by Interscript::Mapping.
var mapcache = Opal.Opal.hash({});

var prom = Promise.all([]);

Object.keys(InterscriptMaps).forEach(function (key) {
	prom = prom.then(function () {
		return Opal.Opal.Interscript.$on_load_maps({ maps: key, path: "../maps/" });
	}).then(function () {
		var map = JSON.parse(InterscriptMaps[key]);
		describe(key + ' system', function () {
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

			map.tests && map.tests.forEach(function (test) {

				if (test['source'] === null || test['expected'] === null)
					return;

				it('test for ' + JSON.stringify(test), function () {
					var result = Opal.Opal.Interscript.$transliterate(key, test['source'], mapcache);
					var expected = test['expected'] && test['expected'].normalize();
					if (result !== expected) console.log(result);
					assert.strictEqual(result, expected);
					//assert.equal(!!result || result === "", true);
				});
			});
		});
	}).catch(function (error) {
		console.log(error);
	});
});
