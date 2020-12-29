class Interscript::Node::Rule::Run < Interscript::Node::Rule
  attr_accessor :stage
  def initialize stage
    @stage = stage
  end

  def to_hash
    { :class => self.class.to_s,
      :stage => self.stage.to_hash }
  end
end
