require 'regexp_parser'


def process(node)
  children = if node.respond_to?(:expressions) && node.expressions
               children = node.expressions.map.each { |expr| process(expr) }
             end
  # puts node.inspect
  out = case node
        when Regexp::Expression::Root
          children
        when Regexp::Expression::Assertion::Lookbehind
          [:lookbehind_start, children, :lookbehind_stop]
        when Regexp::Expression::Assertion::NegativeLookbehind
          [:negative_lookbehind_start, children, :negative_lookbehind_stop]
        when Regexp::Expression::Assertion::Lookahead
          [:lookahead_start, children, :lookahead_stop]
        when Regexp::Expression::Assertion::NegativeLookahead
          [:negative_lookahead_start, children, :negative_lookahead_stop]
        when Regexp::Expression::Group::Capture
          [:capture_start, children, :capture_stop]
        when Regexp::Expression::CharacterSet
          # puts children.inspect
          if children.flatten.include? (:range_start) #or children.size > 1
            [:characterset_start, :array_start, children, :array_stop, :characterset_stop]
          else
            [:characterset_start, children, :characterset_stop]
          end
        when Regexp::Expression::Alternation
          [:alternation_start, children, :alternation_stop]
        when Regexp::Expression::Alternative
          [:alternative_start, children, :alternative_stop]
        when Regexp::Expression::CharacterSet::Range
          lit1 = node.expressions[0].text
          lit2 = node.expressions[1].text
          [:range_start, lit1, :range_mid, lit2, :range_stop]
        when Regexp::Expression::Anchor::WordBoundary
          :boundary
        when Regexp::Expression::Anchor::NonWordBoundary
          :non_word_boundary
        when Regexp::Expression::EscapeSequence::Backspace
          :boundary # most probably boundary
        when Regexp::Expression::CharacterType::Space
          :space
        when Regexp::Expression::Anchor::BeginningOfLine
          :line_start
        when Regexp::Expression::Anchor::EndOfLine
          :line_end
        when Regexp::Expression::CharacterType::Any
          :any_character
        when Regexp::Expression::Literal
          node.text
        when Regexp::Expression::EscapeSequence::Literal
          node.text
        when Regexp::Expression::EscapeSequence::Codepoint
          node.text
        when Regexp::Expression::PosixClass
          '[' + node.text + ']'
        when Regexp::Expression::UnicodeProperty::Script
          node.text
        when Regexp::Expression::Backreference::Number # why is there a space before after node.number?
          [:backref_num_start, node.number, :backref_num_stop]
        else
          out = [:missing, node.class]

          out << children if node.respond_to? :expressions
           if node.respond_to? :quantifier and node.quantifier
            # TODO add quantifier support
            pp node
            # out << process(node.quantifier)
          end
          out
        end
  if node.respond_to?(:quantifier) && node.quantifier&.token.to_s == "interval" && node.quantifier.max == node.quantifier.min
    out = [out] * node.quantifier.max
  elsif node.respond_to?(:quantifier) && node.quantifier
    qname = node.quantifier.token.to_s
    out = ["#{qname}_start".to_sym, [out], "#{qname}_stop".to_sym]
  end
  out
end

def process_root(node)
  node2 = node.dup
  root = {}
  if before = node.select { |x| x[0] == :lookbehind_start }
    # root[:before] = before[1]
    # node2.delete(before)
    if before.size == 1
      root[:before] = before[0][1]
      node2.delete(before[0])
    elsif before.size >1
      # pp not_before

      a = [:alternation_start]
      a << before.map{|x| [:alternative_start, x[1], :alternative_stop] }
      a << [:alternation_stop]
      root[:before] = a
      # pp root[:not_before]
      before.each{|n| node2.delete(n)}
    end

  end
  if not_before = node.select { |x| x[0] == :negative_lookbehind_start }
    # root[:not_before] = not_before[1]
    # node2.delete(not_before)

    if not_before.size == 1
      root[:not_before] = not_before[0][1]
      node2.delete(not_before[0])
    elsif not_before.size >1
      # pp not_before

      a = [:alternation_start]
      a << not_before.map{|x| [:alternative_start, x[1], :alternative_stop] }
      a << [:alternation_stop]
      root[:not_before] = a
      # pp root[:not_before]
      not_before.each{|n| node2.delete(n)}
    end
  end
  if after = node.select { |x| x[0] == :lookahead_start }
    # root[:after] = after[1]
    # node2.delete(after)

    if after.size == 1
      root[:after] = after[0][1]
      node2.delete(after[0])
    elsif after.size >1
      # pp not_before

      a = [:alternation_start]
      a << after.map{|x| [:alternative_start, x[1], :alternative_stop] }
      a << [:alternation_stop]
      root[:after] = a
      # pp root[:not_before]
      after.each{|n| node2.delete(n)}
    end

  end
  if not_after = node.select { |x| x[0] == :negative_lookahead_start }
    # root[:not_after] = not_after[1]
    # node2.delete(not_after)
    if not_after.size == 1
      root[:not_after] = not_after[0][1]
      node2.delete(not_after[0])
    elsif not_after.size >1
      # pp not_after

      a = [:alternation_start]
      a << not_after.map{|x| [:alternative_start, x[1], :alternative_stop] }
      a << [:alternation_stop]
      root[:not_after] = a
      # pp root[:not_after]
      not_after.each{|n| node2.delete(n)}
    end

  end
  root[:from] = node2
  root
end

def stringify(node)
  tokens = node.flatten
  subs = {
    characterset_start: 'any(',
    characterset_stop: ')',
    array_start: '[',
    array_stop: ']',
    capture_start: 'capture(',
    capture_stop: ')',
    zero_or_one_start: 'maybe(',
    zero_or_one_stop: ')',
    zero_or_more_start: 'maybe_some(',
    zero_or_more_stop: ')',
    one_or_more_start: 'some(',
    one_or_more_stop: ')',
    alternation_start: 'any([',
    alternation_stop: '])',
    alternative_start: '',
    alternative_stop: '',
    boundary: 'boundary',
    non_word_boundary: 'non_word_boundary',
    space: 'space',
    line_start: 'line_start',
    line_end: 'line_end',
    any_character: 'any_character',
    range_start: 'any(',
    range_mid: '..',
    range_stop: ')',
    backref_num_start: 'ref(',
    backref_num_stop: ')'
  }

  str = []
  tokens.each_with_index do |token, idx|
    prev = tokens[idx - 1] if idx > 0
    left_side = %i[characterset_stop capture_stop
           zero_or_one_stop zero_or_more_stop one_or_more_stop
           boundary non_word_boundary
           line_start any_character range_stop space
                                           backref_num_stop]
    right_side = %i[characterset_start capture_start
            zero_or_one_start zero_or_more_start one_or_more_start
            boundary non_word_boundary
            line_end any_character range_start space
                                       backref_num_start]
    #if prev==:range_stop and token==:range_start
    #  str << ' :adding_ranges '
    #end
    if (prev.instance_of?(String) && right_side.include?(token)) or
      (left_side.include?(prev) && token.instance_of?(String)) or
      (left_side.include?(prev) && right_side.include?(token))
      str << ' + '
    end
    str << ', ' if prev == :alternative_stop and token == :alternative_start
    # str << '[' if prev == :characterset_start and token == :range_start
    # str << ']' if prev == :range_stop and token ==:characterset_stop
    if subs.include? token
      str << subs[token]
    elsif token.instance_of?(String)
      if prev.instance_of?(String)
        str[-1] = "#{str[-1][0..-2]}#{token}\""
      else
        str << "\"#{token}\""
      end
    else
      str << " #{token.inspect} "
    end
    # puts [idx, token].inspect
    # puts str.inspect
  end
  str.join.gsub('\\\\u', '\\u')
end

def stringify_root(root, indent: 0)
  warning = ''
  root[:from] = [""] if root[:from] == []
  str = " "*indent+"sub #{stringify(root[:from])}, #{root[:to]}"
  [:before, :not_before, :after, :not_after].each do |look|
    # puts "#{look.inspect} = #{root[look]}"
    next unless root[look]
    str_look = stringify(root[look])
    str_look = "\"\"" if root[look] == [] || root[look] == nil
    #if str_look.empty?  #apparently it is empty sometimes. iso-mal-Mlym-Latn for example
    #  warning << "warning: #{look} is empty string;"
    #else
      str << ", #{look}: #{str_look}"
    #end
  end
  str = " "*indent+"# #{str} # warning: :" if str =~ /[^\[]:[^ \]]/
  str = " "*indent+"# #{str} # #{warning}" if !warning.empty?

  str = " "*indent+"# #{str} # warning: :missing unimplemented" if str.include?(':missing')
  str = " "*indent+"# #{str} # warning: :interval unimplemented" if str.include?(':interval')
  str = " "*indent+"# #{str} # warning: :adding_ranges unimplemented" if str.include?(':adding_ranges')
  if str.include?('zero_or_one')
    str = " "*indent+"# #{str} # warning: zero_or_one"
    puts "str.includes 'zero_or_one'"
    pp root
  end
  # str = " "*indent+"# #{str} # warning: one_or_more" if str.include?('one_or_more')
   str = " "*indent+"# #{str} # warning: :lookahead_start" if str.include?(':lookahead_start')
  # str += " # original: #{root[:from]}"
  str
end

if __FILE__ == $0
  rs = File.open(__dir__+"/../../docs/utils/regexp_examples.txt").read.gsub(/([^\\^])\\u/, '\\1\\\\u').gsub(/\\\\b/, '\b')
  rs = rs.split("\n")
  rs.each do |r|
    puts r
    tree = Regexp::Parser.parse(r, 'ruby/2.1')
    conv = process(tree)
    pp conv
    root = process_root(conv)
    pp root
    root[:to] = ['X']
    str = stringify_root(root)
    puts str
    puts "\n\n"
  end
end
