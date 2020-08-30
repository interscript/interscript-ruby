var assert = require('assert');
const { Opal: { Interscript } } = require('../vendor/assets/javascripts/interscript.js');

Object.keys(ISMap).forEach(key => {
	const map = JSON.parse(ISMap[key]);
	describe(`${key} system`, function () {
		map?.tests?.forEach(test => {
			it(`test for ${JSON.stringify(test)}`, function () {
		  		const result = Interscript.$transliterate(key, test["source"]);
				const expected = test["expected"]?.normalize(); 
				assert.strictEqual(result, expected);
			});			
		});		
	});
});