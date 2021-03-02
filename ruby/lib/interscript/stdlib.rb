class Interscript::Stdlib
  ALIASES = {
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
    line_start: "^",
    line_end: "$",
    string_start: "\\A",
    string_end: "\\z"
  }

  def self.re_only_alias?(a)
    ! %i[none space].include?(a)
  end

  @treecache = {}

  def self.parallel_regexp_compile(subs_hash)
    # puts subs_hash.inspect
    regexp = subs_hash.each_with_index.map do |p,i|
      "(?<_%d>%s)" % [i,p[0]]
    end.join("|")
    subs_regexp = Regexp.compile(regexp)
    # puts subs_regexp.inspect
  end

  def self.parallel_regexp_gsub(string, subs_regexp, subs_hash)
    string.gsub(subs_regexp) do |match|
      lm = Regexp.last_match
      # Extract the match name
      idx = lm.named_captures.compact.keys.first[1..-1].to_i
      subs_hash[idx]
    end
  end

  def self.parallel_replace_compile_hash(a)
    h = {}
    a.each do |from,to|
      h[from] = to
    end
    h
  end

  def self.parallel_replace_hash(str,h)
    newstr = ""
    len = str.length
    max_key_len = h.keys.map(&:length).max
    i = 0
    while i < len
      max_key_len.downto(1).each do |checked_len|
        substr = str[i,checked_len]
        if h[substr]
          newstr << h[substr]
          i += substr.length
        elsif checked_len==1
          newstr << str[i,1]
          i += 1
        end
      end
    end
    newstr
  end

  # hash can be either a hash or a hash-like array
  def self.parallel_replace_compile_tree(hash)
    hh = hash.hash
    if @treecache[hh]
      tree = @treecache[hh]
    else
      tree = {}
      hash.each do |from, to|
        from = Array(from)
        from.each do |f|
          branch = tree
          chars = f.split("")
          chars[0..-2].each do |c|
            branch[c.ord] ||= {}
            branch = branch[c.ord]
          end
          branch[chars.last.ord] ||= {}
          branch[chars.last.ord][nil] = to
        end
      end
      @treecache[hh] = tree
    end
  end

  def self.parallel_replace_tree(str, tree)
    newstr = ""
    len = str.length
    i = 0
    while i < len
      c = str[i]

      sub = ""
      branch = tree
      match, repl = nil, nil

      j = 0
      while j < len-i
        cc = str[i+j]
        if branch.include? cc.ord
          branch = branch[cc.ord]
          sub << cc
          if branch.include? nil
            match = sub.dup
            repl = branch[nil]
          end
          j += 1
        else
          break
        end
      end

      if match
        i += match.length
        newstr << repl
      else
        newstr << c
        i += 1
      end
    end
    newstr
  end

  def self.parallel_replace(str, hash)
    tree = parallel_replace_compile_tree(hash)
    parallel_replace_tree(str, tree)
  end

  def self.available_functions
    %i[title_case downcase compose decompose separate]
  end

  module Functions
    def self.title_case(output, word_separator: " ")
      output = output.gsub(/^(.)/, &:upcase)
      output = output.gsub(/#{word_separator}(.)/, &:upcase) unless word_separator == ''
      output
    end

    def self.downcase(output)
      output.downcase
    end

    def self.compose(output)
      output.unicode_normalize(:nfc)
    end

    def self.decompose(output)
      output.unicode_normalize(:nfd)
    end

    def self.separate(output, separator: " ")
      output.split("").join(separator)
    end
  end
end
