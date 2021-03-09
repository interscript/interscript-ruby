"use strict";

var Interscript = {
  aliases: {
    any_character: '.',
    none: "",
    space: " ",
    whitespace: "[\\b \\t\\0\\r\\n]",
    boundary: "\\b", // TODO: handle non-ascii
    non_word_boundary: "\\B",
    word: "\\w",
    not_word: "\\W",
    alpha: "[a-zA-Z]",
    not_alpha: "[^a-zA-Z]",
    digit: "\\d",
    not_digit: "\\D",
    line_start: "(?<=\n|^)",
    line_end: "(?=\n|$)",
    string_start: "^",
    string_end: "$"
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
}
