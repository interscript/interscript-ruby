require 'regexp_parser'


def process( node )
  children = if node.respond_to? :expressions and node.expressions
    children = node.expressions.map.each{ |expr| process(expr) }
  end
  #puts node.class
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
    [:characterset_start, children, :characterset_stop]

  when Regexp::Expression::CharacterSet::Range
    lit1 = node.expressions[0].text
    lit2 = node.expressions[1].text
    [:range_start, lit1, :range_mid, lit2, :range_stop]
  when Regexp::Expression::Anchor::WordBoundary
    :boundary
  when Regexp::Expression::Anchor::BeginningOfLine
    :line_start
  when Regexp::Expression::Anchor::EndOfLine
    :line_end
  when Regexp::Expression::Literal
    node.text
  when Regexp::Expression::EscapeSequence::Literal
    node.text
  when Regexp::Expression::EscapeSequence::Codepoint
    node.text
  else
    out = [:missing, node.class]

    if node.respond_to? :expressions
      out << children
    end
    if node.quantifier
      out << process(node.quantifier)
    end
    out
  end
  if node.respond_to? :quantifier and node.quantifier
    qname = node.quantifier.token.to_s
    out = ["#{qname}_start".to_sym, [out], "#{qname}_stop".to_sym]
  end
  out
end

def process_root(node)
  node2 = node.dup
  root = {}
  if before = node.select{|x| x[0] == :lookbehind_start}[0]
    root[:before] = before[1]
    node2.delete(before)
  end
  if not_before = node.select{|x| x[0] == :negative_lookbehind_start}[0]
    root[:not_before] = not_before[1]
    node2.delete(not_before)
  end
  if after = node.select{|x| x[0] == :lookahead_start}[0]
    root[:after] = after[1]
    node2.delete(after)
  end
  if not_after = node.select{|x| x[0] == :negative_lookahead_start}[0]
    root[:not_after] = not_after[1]
    node2.delete(not_after)
  end
  root[:from] = node2
  root
end


def stringify(node)
  tokens = node.flatten
  subs = {
  :characterset_start => 'any(',
  :characterset_stop => ')',
  :capture_start => 'capture(',
  :capture_stop => ')',
  :zero_or_one_start => 'zero_or_one(',
  :zero_or_one_stop => ')',
  :boundary => 'boundary',
  :line_start => 'line_start',
  :line_end => 'line_end',
  :range_start => "",
  :range_mid => "..", 
  :range_stop => ""}

  str = []
  tokens.each_with_index do |token,idx|
    prev = tokens[idx-1] if idx>0
    if prev.class == String and [:characterset_start, :capture_start,
      :zero_or_one_start, :boundary, :line_end, :range_start].include? token
      str << ' + '
    elsif token.class == String and [:characterset_stop, :capture_stop,
      :zero_or_one_stop, :boundary, :line_start, :range_stop].include? prev
      str << ' + '
    end
    if subs.include? token
      str << subs[token] 
    elsif token.class == String
      if prev.class == String
        str[-1] = str[-1][0..-2] + token + '"'
      else
        str << "\"#{token}\""
      end
    else
      str << ' ' + token.inspect + ' '
    end
    #puts [idx, token].inspect
    #puts str.inspect

  end
  str.join.gsub("\\\\u","\\u")
end


def stringify_root(root)
  str = "sub #{stringify(root[:from])}, #{stringify( root[:to] )}"
  str << ", before: #{stringify(root[:before])}" if root[:before]
  str << ", not_before: #{stringify(root[:not_before])}" if root[:not_before]
  str << ", after: #{stringify(root[:after])}" if root[:after]
  str << ", not_after: #{stringify(root[:not_after])}" if root[:not_after]
  str
end

rs = File.open("regexp_examples.txt").read.gsub(/([^\\^])\\u/,'\\1\\\\u').gsub(/\\\\b/,'\b')

rs = rs.split("\n")
conv = nil

rs.each do |r|
  puts r
  tree = Regexp::Parser.parse( r, 'ruby/2.1' );
  conv = process(tree)
  # pp conv
  root = process_root(conv)
  # pp root
  root[:to] = ['X']
  str = stringify_root(root)
  puts str
  puts "\n\n"
end
