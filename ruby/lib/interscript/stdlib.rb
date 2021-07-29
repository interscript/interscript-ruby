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

  def self.boundary_like_alias?(a)
    %i[line_start line_end string_start string_end boundary non_word_boundary].include?(a)
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

  def self.parallel_regexp_gsub_debug(string, subs_regexp, subs_array)
    # only gathering debug info, test data is available in maps_analyze_staging
    $subs_matches = []
    $subs_regexp = subs_regexp
    #$subs_array = subs_array
    string.gsub(subs_regexp) do |match|
      lm = Regexp.last_match
      # puts lm.inspect
      # Extract the match name
      matched = lm.named_captures.compact.keys.first
      # puts matched.inspect
      # puts [lm.begin(matched), lm.end(matched)].inspect
      idx = matched[1..-1].to_i
      debug_info = {begin: lm.begin(matched), end: lm.end(matched), idx: idx, result: subs_array[idx]}
      $subs_matches << debug_info
      subs_array[idx]
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

  # On Windows at least, sort_by is non-deterministic. Let's add some determinism
  # to our efforts.
  def self.deterministic_sort_by_max_length(ary)
    # Deterministic on Linux:
    # ary.sort_by{ |rule| -rule.max_length }

    ary.each_with_index.sort_by{ |rule,idx| -rule.max_length*100000 + idx }.map(&:first)
  end

  def self.available_functions
    %i[title_case downcase compose decompose separate unseparate secryst]
  end

  def self.reverse_function
    {
      title_case: :downcase, # Those two are best-effort,
      downcase: :title_case, # but probably wrong.

      compose: :decompose,
      decompose: :compose,

      separate: :unseparate,
      unseparate: :separate
    }
  end

  module Functions
    def self.title_case(output, word_separator: " ")
      output = output.gsub(/^(.)/, &:upcase)
      output = output.gsub(/#{word_separator}(.)/, &:upcase) unless word_separator == ''
      output
    end

    def self.downcase(output, word_separator: nil)
      if word_separator
        output = output.gsub(/^(.)/, &:downcase)
        output = output.gsub(/#{word_separator}(.)/, &:downcase) unless word_separator == ''
      else
        output.downcase
      end
    end

    def self.compose(output, _:nil)
      output.unicode_normalize(:nfc)
    end

    def self.decompose(output, _:nil)
      output.unicode_normalize(:nfd)
    end

    def self.separate(output, separator: " ")
      output.split("").join(separator)
    end

    def self.unseparate(output, separator: " ")
      output.split(separator).join("")
    end

    @secryst_models = {}
    def self.secryst(output, model:)
      require "secryst" rescue nil # Try to load secryst, but don't fail hard if not possible.
      unless defined? Secryst
        raise StandardError, "Secryst is not loaded. Please read docs/Usage_with_Secryst.adoc"
      end
      Interscript.secryst_index_locations.each do |remote|
        Secryst::Provisioning.add_remote(remote)
      end
      @secryst_models[model] ||= Secryst::Translator.new(model_file: model)
      output.split("\n").map(&:chomp).map do |i|
        @secryst_models[model].translate(i)
      end.join("\n")
    end
  end
end
