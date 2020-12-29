class Interscript::Node::Rule::Sub < Interscript::Node::Rule
  attr_accessor :from, :to
  attr_accessor :before, :not_before, :after, :not_after

  def initialize from, to, before: nil, not_before: nil, after: nil, not_after: nil

    self.from = Interscript::Node::Item.try_convert from
    self.to = Interscript::Node::Item.try_convert to

    raise TypeError, "Can't supply both before and not_before" if before && not_before
    raise TypeError, "Can't supply both after and not_after" if after && not_after

    self.before = Interscript::Node::Item.try_convert(before) if before
    self.after = Interscript::Node::Item.try_convert(after) if after
    self.not_before = Interscript::Node::Item.try_convert(not_before) if not_before
    self.not_after = Interscript::Node::Item.try_convert(not_after) if not_after
  end

  def to_hash
    puts self.from.inspect if $DEBUG
    puts params.inspect if $DEBUG
    { :class => self.class.to_s,
      :from => self.from.to_hash,
      :to => self.to.to_hash,
      :before => self.before,
      :not_before => self.not_before,
      :after => self.after,
      :not_after => self.not_after
    }
  end
end
