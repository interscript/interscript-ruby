class Interscript::Node::Item
  class Alias < self
    def to_html(doc)
      if map
        n = doc.dep_aliases[map].full_name
        "#{name.to_s.gsub("_", " ")} from map #{n}"
      else
        "#{name.to_s.gsub("_", " ")}"
      end
    end
  end

  class Stage < self
    def to_html(doc)
      if map
        n = doc.dep_aliases[map].full_name
        "stage #{name.to_s.gsub("_", " ")} from map #{n}"
      else
        "#{name.to_s.gsub("_", " ")}"
      end
    end
  end

  class Any < self
    def to_html(doc)
      "<nobr>any (</nobr>" +
        case @value
        when Array
          value.map(&Interscript::Node::Item.method(:try_convert)).map{|i|i.to_html(doc)}.join(", ")
        when ::String
          value.split("").map(&Interscript::Node::Item.method(:try_convert)).map{|i|i.to_html(doc)}.join(", ")
        when Range
          [value.begin, value.end].map(&Interscript::Node::Item.method(:try_convert)).map{|i|i.to_html(doc)}.join(" to ")
        else
          h(value.inspect)
        end +
      ")"
    end
  end

  class CaptureGroup < self
    def to_html(doc)
      "<nobr>capture group (</nobr>" +
        data.to_html(doc) +
      ")"
    end
  end

  class CaptureRef < self
    def to_html(_)
      "<nobr>capture reference (</nobr>" +
        id.to_s +
      ")"
    end
  end

  class Group < self
    def to_html(doc)
      @children.map{|i|i.to_html(doc)}.join(" + ")
    end
  end

  class Repeat < self
    def to_html(doc)
      str = case self
      when Interscript::Node::Item::Maybe
        "zero or one "
      when Interscript::Node::Item::MaybeSome
        "zero or more of "
      when Interscript::Node::Item::Some
        "one or more of "
      end
      "<nobr>#{str}(</nobr>#{@data.to_html(doc)})"
    end
  end

  class String < self
    def to_html(_)
      out = ""
      self.data.each_char do |i|
        out << "<ruby>"
        out << "<kbd>#{h i}</kbd>"
        out << "<rt>#{"%04x" % i.ord}</rt>"
        out << "</ruby>"
      end
      out
    end
  end
end