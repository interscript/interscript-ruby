"use strict";

var Interscript = {
  aliases: {
    any_character: '.',
    none: "",
    space: " ",
    whitespace: "[\\b \\t\\0\\r\\n]",
    boundary: "\\b",
    non_word_boundary: "\\B",
    word: "\\w",
    not_word: "\\W",
    alpha: "[a-zA-Z]",
    not_alpha: "[^a-zA-Z]",
    digit: "\\d",
    not_digit: "\\D",
    line_start: "(?<=\\n|^)",
    line_end: "(?=\\n|$)",
    string_start: "^",
    string_end: "$"
  },

  correct_boundaries: function() {
    var word = "\\u0030-\\u0039\\u0041-\\u005a\\u005f\\u0061-\\u007a\\u00aa\\u00b2-\\u00b3\\u00b5\\u00b9-\\u00ba\\u00bc-\\u00be\\u00c0-\\u00d6\\u00d8-\\u00f6\\u00f8-\\u02c1\\u02c6-\\u02d1\\u02e0-\\u02e4\\u02ec\\u02ee\\u0300-\\u0374\\u0376-\\u0377\\u037a-\\u037d\\u037f\\u0386\\u0388-\\u038a\\u038c\\u038e-\\u03a1\\u03a3-\\u03f5\\u03f7-\\u0481\\u0483-\\u052f\\u0531-\\u0556\\u0559\\u0560-\\u0588\\u0591-\\u05bd\\u05bf\\u05c1-\\u05c2\\u05c4-\\u05c5\\u05c7\\u05d0-\\u05ea\\u05ef-\\u05f2\\u0610-\\u061a\\u0620-\\u0669\\u066e-\\u06d3\\u06d5-\\u06dc\\u06df-\\u06e8\\u06ea-\\u06fc\\u06ff\\u0710-\\u074a\\u074d-\\u07b1\\u07c0-\\u07f5\\u07fa\\u07fd\\u0800-\\u082d\\u0840-\\u085b\\u0860-\\u086a\\u08a0-\\u08b4\\u08b6-\\u08bd\\u08d3-\\u08e1\\u08e3-\\u0963\\u0966-\\u096f\\u0971-\\u0983\\u0985-\\u098c\\u098f-\\u0990\\u0993-\\u09a8\\u09aa-\\u09b0\\u09b2\\u09b6-\\u09b9\\u09bc-\\u09c4\\u09c7-\\u09c8\\u09cb-\\u09ce\\u09d7\\u09dc-\\u09dd\\u09df-\\u09e3\\u09e6-\\u09f1\\u09fc\\u09fe\\u0a01-\\u0a03\\u0a05-\\u0a0a\\u0a0f-\\u0a10\\u0a13-\\u0a28\\u0a2a-\\u0a30\\u0a32-\\u0a33\\u0a35-\\u0a36\\u0a38-\\u0a39\\u0a3c\\u0a3e-\\u0a42\\u0a47-\\u0a48\\u0a4b-\\u0a4d\\u0a51\\u0a59-\\u0a5c\\u0a5e\\u0a66-\\u0a75\\u0a81-\\u0a83\\u0a85-\\u0a8d\\u0a8f-\\u0a91\\u0a93-\\u0aa8\\u0aaa-\\u0ab0\\u0ab2-\\u0ab3\\u0ab5-\\u0ab9\\u0abc-\\u0ac5\\u0ac7-\\u0ac9\\u0acb-\\u0acd\\u0ad0\\u0ae0-\\u0ae3\\u0ae6-\\u0aef\\u0af9-\\u0aff\\u0b01-\\u0b03\\u0b05-\\u0b0c\\u0b0f-\\u0b10\\u0b13-\\u0b28\\u0b2a-\\u0b30\\u0b32-\\u0b33\\u0b35-\\u0b39\\u0b3c-\\u0b44\\u0b47-\\u0b48\\u0b4b-\\u0b4d\\u0b56-\\u0b57\\u0b5c-\\u0b5d\\u0b5f-\\u0b63\\u0b66-\\u0b6f\\u0b71\\u0b82-\\u0b83\\u0b85-\\u0b8a\\u0b8e-\\u0b90\\u0b92-\\u0b95\\u0b99-\\u0b9a\\u0b9c\\u0b9e-\\u0b9f\\u0ba3-\\u0ba4\\u0ba8-\\u0baa\\u0bae-\\u0bb9\\u0bbe-\\u0bc2\\u0bc6-\\u0bc8\\u0bca-\\u0bcd\\u0bd0\\u0bd7\\u0be6-\\u0bef\\u0c00-\\u0c0c\\u0c0e-\\u0c10\\u0c12-\\u0c28\\u0c2a-\\u0c39\\u0c3d-\\u0c44\\u0c46-\\u0c48\\u0c4a-\\u0c4d\\u0c55-\\u0c56\\u0c58-\\u0c5a\\u0c60-\\u0c63\\u0c66-\\u0c6f\\u0c80-\\u0c83\\u0c85-\\u0c8c\\u0c8e-\\u0c90\\u0c92-\\u0ca8\\u0caa-\\u0cb3\\u0cb5-\\u0cb9\\u0cbc-\\u0cc4\\u0cc6-\\u0cc8\\u0cca-\\u0ccd\\u0cd5-\\u0cd6\\u0cde\\u0ce0-\\u0ce3\\u0ce6-\\u0cef\\u0cf1-\\u0cf2\\u0d00-\\u0d03\\u0d05-\\u0d0c\\u0d0e-\\u0d10\\u0d12-\\u0d44\\u0d46-\\u0d48\\u0d4a-\\u0d4e\\u0d54-\\u0d57\\u0d5f-\\u0d63\\u0d66-\\u0d6f\\u0d7a-\\u0d7f\\u0d82-\\u0d83\\u0d85-\\u0d96\\u0d9a-\\u0db1\\u0db3-\\u0dbb\\u0dbd\\u0dc0-\\u0dc6\\u0dca\\u0dcf-\\u0dd4\\u0dd6\\u0dd8-\\u0ddf\\u0de6-\\u0def\\u0df2-\\u0df3\\u0e01-\\u0e3a\\u0e40-\\u0e4e\\u0e50-\\u0e59\\u0e81-\\u0e82\\u0e84\\u0e86-\\u0e8a\\u0e8c-\\u0ea3\\u0ea5\\u0ea7-\\u0ebd\\u0ec0-\\u0ec4\\u0ec6\\u0ec8-\\u0ecd\\u0ed0-\\u0ed9\\u0edc-\\u0edf\\u0f00\\u0f18-\\u0f19\\u0f20-\\u0f29\\u0f35\\u0f37\\u0f39\\u0f3e-\\u0f47\\u0f49-\\u0f6c\\u0f71-\\u0f84\\u0f86-\\u0f97\\u0f99-\\u0fbc\\u0fc6\\u1000-\\u1049\\u1050-\\u109d\\u10a0-\\u10c5\\u10c7\\u10cd\\u10d0-\\u10fa\\u10fc-\\u1248\\u124a-\\u124d\\u1250-\\u1256\\u1258\\u125a-\\u125d\\u1260-\\u1288\\u128a-\\u128d\\u1290-\\u12b0\\u12b2-\\u12b5\\u12b8-\\u12be\\u12c0\\u12c2-\\u12c5\\u12c8-\\u12d6\\u12d8-\\u1310\\u1312-\\u1315\\u1318-\\u135a\\u135d-\\u135f\\u1380-\\u138f\\u13a0-\\u13f5\\u13f8-\\u13fd\\u1401-\\u166c\\u166f-\\u167f\\u1681-\\u169a\\u16a0-\\u16ea\\u16ee-\\u16f8\\u1700-\\u170c\\u170e-\\u1714\\u1720-\\u1734\\u1740-\\u1753\\u1760-\\u176c\\u176e-\\u1770\\u1772-\\u1773\\u1780-\\u17d3\\u17d7\\u17dc-\\u17dd\\u17e0-\\u17e9\\u180b-\\u180d\\u1810-\\u1819\\u1820-\\u1878\\u1880-\\u18aa\\u18b0-\\u18f5\\u1900-\\u191e\\u1920-\\u192b\\u1930-\\u193b\\u1946-\\u196d\\u1970-\\u1974\\u1980-\\u19ab\\u19b0-\\u19c9\\u19d0-\\u19d9\\u1a00-\\u1a1b\\u1a20-\\u1a5e\\u1a60-\\u1a7c\\u1a7f-\\u1a89\\u1a90-\\u1a99\\u1aa7\\u1ab0-\\u1abe\\u1b00-\\u1b4b\\u1b50-\\u1b59\\u1b6b-\\u1b73\\u1b80-\\u1bf3\\u1c00-\\u1c37\\u1c40-\\u1c49\\u1c4d-\\u1c7d\\u1c80-\\u1c88\\u1c90-\\u1cba\\u1cbd-\\u1cbf\\u1cd0-\\u1cd2\\u1cd4-\\u1cfa\\u1d00-\\u1df9\\u1dfb-\\u1f15\\u1f18-\\u1f1d\\u1f20-\\u1f45\\u1f48-\\u1f4d\\u1f50-\\u1f57\\u1f59\\u1f5b\\u1f5d\\u1f5f-\\u1f7d\\u1f80-\\u1fb4\\u1fb6-\\u1fbc\\u1fbe\\u1fc2-\\u1fc4\\u1fc6-\\u1fcc\\u1fd0-\\u1fd3\\u1fd6-\\u1fdb\\u1fe0-\\u1fec\\u1ff2-\\u1ff4\\u1ff6-\\u1ffc\\u203f-\\u2040\\u2054\\u2071\\u207f\\u2090-\\u209c\\u20d0-\\u20f0\\u2102\\u2107\\u210a-\\u2113\\u2115\\u2119-\\u211d\\u2124\\u2126\\u2128\\u212a-\\u212d\\u212f-\\u2139\\u213c-\\u213f\\u2145-\\u2149\\u214e\\u2160-\\u2188\\u24b6-\\u24e9\\u2c00-\\u2c2e\\u2c30-\\u2c5e\\u2c60-\\u2ce4\\u2ceb-\\u2cf3\\u2d00-\\u2d25\\u2d27\\u2d2d\\u2d30-\\u2d67\\u2d6f\\u2d7f-\\u2d96\\u2da0-\\u2da6\\u2da8-\\u2dae\\u2db0-\\u2db6\\u2db8-\\u2dbe\\u2dc0-\\u2dc6\\u2dc8-\\u2dce\\u2dd0-\\u2dd6\\u2dd8-\\u2dde\\u2de0-\\u2dff\\u2e2f\\u3005-\\u3007\\u3021-\\u302f\\u3031-\\u3035\\u3038-\\u303c\\u3041-\\u3096\\u3099-\\u309a\\u309d-\\u309f\\u30a1-\\u30fa\\u30fc-\\u30ff\\u3105-\\u312f\\u3131-\\u318e\\u31a0-\\u31ba\\u31f0-\\u31ff\\u3400-\\u4db5\\u4e00-\\u9fef\\ua000-\\ua48c\\ua4d0-\\ua4fd\\ua500-\\ua60c\\ua610-\\ua62b\\ua640-\\ua672\\ua674-\\ua67d\\ua67f-\\ua6f1\\ua717-\\ua71f\\ua722-\\ua788\\ua78b-\\ua7bf\\ua7c2-\\ua7c6\\ua7f7-\\ua827\\ua840-\\ua873\\ua880-\\ua8c5\\ua8d0-\\ua8d9\\ua8e0-\\ua8f7\\ua8fb\\ua8fd-\\ua92d\\ua930-\\ua953\\ua960-\\ua97c\\ua980-\\ua9c0\\ua9cf-\\ua9d9\\ua9e0-\\ua9fe\\uaa00-\\uaa36\\uaa40-\\uaa4d\\uaa50-\\uaa59\\uaa60-\\uaa76\\uaa7a-\\uaac2\\uaadb-\\uaadd\\uaae0-\\uaaef\\uaaf2-\\uaaf6\\uab01-\\uab06\\uab09-\\uab0e\\uab11-\\uab16\\uab20-\\uab26\\uab28-\\uab2e\\uab30-\\uab5a\\uab5c-\\uab67\\uab70-\\uabea\\uabec-\\uabed\\uabf0-\\uabf9\\uac00-\\ud7a3\\ud7b0-\\ud7c6\\ud7cb-\\ud7fb\\uf900-\\ufa6d\\ufa70-\\ufad9\\ufb00-\\ufb06\\ufb13-\\ufb17\\ufb1d-\\ufb28\\ufb2a-\\ufb36\\ufb38-\\ufb3c\\ufb3e\\ufb40-\\ufb41\\ufb43-\\ufb44\\ufb46-\\ufbb1\\ufbd3-\\ufd3d\\ufd50-\\ufd8f\\ufd92-\\ufdc7\\ufdf0-\\ufdfb\\ufe00-\\ufe0f\\ufe20-\\ufe2f\\ufe33-\\ufe34\\ufe4d-\\ufe4f\\ufe70-\\ufe74\\ufe76-\\ufefc\\uff10-\\uff19\\uff21-\\uff3a\\uff3f\\uff41-\\uff5a\\uff66-\\uffbe\\uffc2-\\uffc7\\uffca-\\uffcf\\uffd2-\\uffd7\\uffda\\uffdc";
    var non_word = "[^"+word+"]";
    word = "["+word+"]";

    this.aliases.boundary = "(?:^(?="+word+")|(?<="+word+")$|(?<="+word+")(?="+non_word+")|(?<="+non_word+")(?="+word+"))";
    this.aliases.non_word_boundary = "(?:^(?="+non_word+")|(?<="+non_word+")$|(?<="+word+")(?="+word+")|(?<="+non_word+")(?="+non_word+"))";
  },

  available_functions: ["title_case", "downcase", "compose", "decompose", "separate"],

  mkregexp: function(str) {
    return XRegExp(str, "g");
  },

  regexp_escape: function(a) {
    return a.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  },

  parallel_replace_tree: function(str, tree) {
    var newstr = "";
    var len = str.length;
    var i = 0;
    while (i < len) {
      var c = str[i];

      var sub = "";
      var branch = tree;
      var match = null;
      var repl = null;

      var j = 0;
      while (j < len-i) {
        var cc = str[i+j];
        if (branch[cc.charCodeAt(0)]) {
          branch = branch[cc.charCodeAt(0)];
          sub += cc;
          if (branch[""] !== undefined) {
            match = sub;
            repl = branch[""];
          }
          j += 1;
        }
        else {
          break;
        }
      }

      if (match) {
        i += match.length;
        newstr += repl;
      }
      else {
        newstr += c;
        i += 1;
      }
    }
    return newstr;
  },

  parallel_regexp_gsub: function(s, data) {
    return XRegExp.replace(s, this.mkregexp(data[0]), function(match) {
      var matches = arguments[arguments.length - 1];
      var idx;
      for (var i in matches) {
        if (matches[i] !== undefined) idx = i;
      }
      return data[1][idx.replace("_", "")];
    });
  },

  gsub: function(s, from, to) {
    return s.replace(this.mkregexp(from), to);
  },

  maps: {},

  define_map: function(map, fun) {
    this.maps[map] = {
      name: map,
      aliases: {},
      aliases_re: {},
      cache: {},
      stages: {}
    };
    fun(this, this.maps[map]);
  },

  get_alias: function(map, alias) {
    return this.maps[map].aliases[alias];
  },

  get_alias_re: function(map, alias) {
    return this.maps[map].aliases_re[alias];
  },

  transcribe: function(map, str, stage) {
    if (stage === undefined) stage = "main";
    return this.maps[map].stages[stage](str);
  },

  functions: {
    title_case: function(output, opts) {
      if(opts.word_separator === undefined) opts.word_separator = " "
      output = output.replace(/(^|\n)(.)/g, function(a) {
        return a.toUpperCase();
      });
      if(opts.word_separator != "") {
        var sep = Interscript.regexp_escape(opts.word_separator);
        output = output.replace(new RegExp(sep+"(.)", "g"), function(a) {
          return a.toUpperCase();
        });
      }
      return output;
    },

    downcase: function(output, opts) {
      return output.toLowerCase();
    },

    compose: function(output, opts) {
      return output.normalize("NFC");
    },

    decompose: function(output, opts) {
      return output.normalize("NFD");
    },

    separate: function(output, opts) {
      if (opts.separator === undefined) opts.separator = " ";
      return output.split("").join(opts.separator);
    }
  }
};

Interscript.correct_boundaries();
