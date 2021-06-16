class Interscript::Node::Rule::Sub < Interscript::Node::Rule
  attr_accessor :from, :to
  attr_accessor :before, :not_before, :after, :not_after
  attr_accessor :reverse_before, :reverse_not_before, :reverse_after, :reverse_not_after
  attr_accessor :reverse_run
  attr_accessor :priority

  def initialize (from, to,
                  before: nil, not_before: nil,
                  after: nil, not_after: nil,
                  priority: nil, reverse_run: nil)
    self.from = Interscript::Node::Item.try_convert from
    if to == :upcase
      self.to = :upcase
    elsif to == :downcase
      self.to = :downcase
    else
      self.to = Interscript::Node::Item.try_convert to
    end

    self.priority = priority

    #raise TypeError, "Can't supply both before and not_before" if before && not_before
    #raise TypeError, "Can't supply both after and not_after" if after && not_after

    self.reverse_run = reverse_run

    self.before = Interscript::Node::Item.try_convert(before) if before
    self.after = Interscript::Node::Item.try_convert(after) if after
    self.not_before = Interscript::Node::Item.try_convert(not_before) if not_before
    self.not_after = Interscript::Node::Item.try_convert(not_after) if not_after
  end

  def max_length
    len = self.from.max_length
    len += self.before.max_length if self.before
    len += self.after.max_length if self.after
    len += self.not_before.max_length if self.not_before
    len += self.not_after.max_length if self.not_after
    len += self.priority if self.priority
    len
  end

  def to_hash
    puts self.from.inspect if $DEBUG
    puts params.inspect if $DEBUG
    hash = { :class => self.class.to_s,
      :from => self.from.to_hash,
      :to => Symbol === self.to ? self.to : self.to.to_hash,
      :reverse_run => self.reverse_run,
      :before => self.before&.to_hash,
      :not_before => self.not_before&.to_hash,
      :after => self.after&.to_hash,
      :not_after => self.not_after&.to_hash,
      :priority => self.priority
    }

    hash[:before] = self.before&.to_hash if self.before
    hash[:not_before] = self.not_before&.to_hash if self.not_before
    hash[:after] = self.after&.to_hash if self.after
    hash[:not_after] = self.not_after&.to_hash if self.not_after
    hash[:priority] = self.priority if self.priority

    hash
  end

  def reverse
    if to == :upcase
      xfrom = from.downcase
      xto = :downcase
    elsif to == :downcase
      xfrom = from.upcase
      xto = :upcase
    else
      xto, xfrom = reverse_transfer(from, to)
    end

    # A special case: sub "a", "" shouldn't be present in a reverse map
    rrun = self.reverse_run.nil? ? nil : !self.reverse_run
    if rrun.nil? && !has_assertions? &&
      (xfrom == "" ||
        (Interscript::Node::Item::String === xfrom && xfrom.data == '') ||
        (Interscript::Node::Item::Alias === xfrom && xfrom.name == :none)
      )

      rrun = true
    end

    Interscript::Node::Rule::Sub.new(xfrom, xto,
      before: before, after: after,
      not_before: not_before, not_after: not_after,

      reverse_run: rrun,

      priority: priority ? -priority : nil
    )
  end
  
  def has_assertions?
    !!(before || not_before || not_after || after)
  end

  # Attempt to transfer some references to boundary/line_begin around.
  # Those in general should go into before/after clauses, but for now
  # let's try to get the best compatibility possible. Also, CaptureGroup,
  # CaptureRef need to be shifted around
  def reverse_transfer from, to
    # This part is about moving initial and final boundary like aliases
    case from
    when Interscript::Node::Item::Group
      first = from.children.first
      last = from.children.last

      if Interscript::Node::Item::Alias === first && first.boundary_like?
        out = Interscript::Node::Item::Group.new + first + to
        to = out.compact

        from = from.dup.tap do |i|
          i.children = i.children[1..-1]
        end.compact
      end

      if Interscript::Node::Item::Alias === last && last.boundary_like?
        out = Interscript::Node::Item::Group.new + to + last
        to = out.compact

        from = from.dup.tap do |i|
          i.children = i.children[0..-2]
        end.compact
      end
    when Interscript::Node::Item::Alias
      if from.boundary_like?
        to = if from.name.to_s.end_with? "_end"
          Interscript::Node::Item::Group.new + to + from
        else
          Interscript::Node::Item::Group.new + from + to
        end
        from = Interscript::Node::Item::Alias.new(:none)
      end
    end

    # This part is about moving backreferences
    state = {left:[], right:[]}

    from  = reverse_transfer_visit(from, :from, state)
    to    = reverse_transfer_visit(to,   :to,   state)

    [from, to]
  end

  private def reverse_transfer_visit(node, type, state)
    node = Interscript::Node::Item.try_convert(node)

    case node
    when Interscript::Node::Item::Alias
      if node.name == :kor_maybedash
        state[:left] << node
        Interscript::Node::Item::CaptureRef.new(state[:left].length)
      else
        node
      end
    when Interscript::Node::Item::String
      node
    when Interscript::Node::Item::Any
      if Array === node.value
        node.dup.tap do |i|
          i.value = i.value.map { |c| reverse_transfer_visit(c, type, state) }
        end
      else
        node
      end
    when Interscript::Node::Item::Group
      node.dup.tap do |i|
        i.children = i.children.map { |c| reverse_transfer_visit(c, type, state) }
      end
    when Interscript::Node::Item::Repeat
      node.dup.tap do |i|
        i.data = reverse_transfer_visit(i.data, type, state)
      end
    when Interscript::Node::Item::CaptureRef
      if type == :from
        node
      elsif state[:right][node.id]
        node
      else
        state[:right][node.id] = true
        state[:left][node.id - 1] or raise "Capture count doesn't match"
      end
    when Interscript::Node::Item::CaptureGroup
      state[:left] << node
      out = Interscript::Node::Item::CaptureRef.new(state[:left].length)
      reverse_transfer_visit(node.data, type, state) # Visit but don't care
      out
    else
      raise "Type #{node.class} unhandled!"
    end
  end

  def inspect
    out = "sub "
    params = []
    params << @from.inspect
    if Symbol === @to
      params << @to.to_s
    else
      params << @to.inspect
    end
    params << "reverse_run: #{@reverse_run.inspect}" unless @reverse_run.nil?

    params << "before: #{@before.inspect}" if @before
    params << "after: #{@after.inspect}" if @after
    params << "not_before: #{@not_before.inspect}" if @not_before
    params << "not_after: #{@not_after.inspect}" if @not_after

    params << "priority: #{@priority.inspect}" if @priority
    out << params.join(", ")
  end
end
