class Interscript::Node::Group
  def to_visualization_array(map=self)
    out = []

    self.children.each do |rule|
      case rule
      when Interscript::Node::Rule::Sub
        more = []
        more << "before: #{rule.before.to_html(map)}" if rule.before
        more << "after: #{rule.after.to_html(map)}" if rule.after
        more << "<nobr>not before:</nobr> #{rule.not_before.to_html(map)}" if rule.not_before
        more << "<nobr>not after:</nobr> #{rule.not_after.to_html(map)}" if rule.not_after
        more << "<nobr>reverse run:</nobr> #{rule.reverse_run}" unless rule.reverse_run.nil?
        more = more.join(", ")

        out << {
          type: "Replace",
          from: rule.from.to_html(map),
          to: Symbol === rule.to ? rule.to : rule.to.to_html(map),
          more: more
        }
      when Interscript::Node::Group::Parallel
        out << {
          type: "Parallel",
          children: rule.to_visualization_array(map)
        }
      when Interscript::Node::Rule::Funcall
        more = rule.kwargs.map do |k,v|
          "#{k.to_s.gsub("_", " ")}: #{v}"
        end
        more << "<nobr>reverse run:</nobr> #{rule.reverse_run}" unless rule.reverse_run.nil?

        out << {
          type: rule.name.to_s.gsub("_", " ").gsub(/^(.)/, &:upcase),
          more: more.join(", ")
        }
      when Interscript::Node::Rule::Run
        if rule.stage.map
          doc = map.dep_aliases[rule.stage.map].document
          stage = rule.stage.name
        else
          doc = map
          stage = rule.stage.name
        end

        more = []
        more << "<nobr>reverse run:</nobr> #{rule.reverse_run}" unless rule.reverse_run.nil?

        out << {
          type: "Run",
          doc: doc.name,
          stage: stage,
          more: more.join(", "),
        }
      else
        out << {
          type: "Unknown",
          more: "<pre>#{h rule.inspect}</pre>"
        }
      end
    end

    out
  end
end