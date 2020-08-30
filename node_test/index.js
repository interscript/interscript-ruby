const assert = require('assert');
const { Opal: { Interscript } } = require('../vendor/assets/javascripts/interscript.js');

// const str = "Эх, тройка! птица тройка, кто тебя выдумал? знать, у бойкого народа ты";
// const sysCode = 'bgnpcgn-rus-Cyrl-Latn-1947';
// const output = is.$transliterate(sysCode, str);
// console.log(output);

Object.keys(ISMap).forEach(key => {
	console.log(`${key} system`);
	const map = JSON.parse(ISMap[key]);
	map?.tests?.forEach(test => {
		console.log(`test for ${JSON.stringify(test)}`);
		try{
			const result = Interscript.$transliterate(key, test["source"]);
			const expected = test["expected"]?.normalize(); 
			assert.strictEqual(result, expected, 'PASSED');
		}catch(e){
			console.log('FAILED!');
			// console.log(e);
		}
	})
})
