class Interscript::Node::Rule::Run < Interscript::Node::Rule
  attr_accessor :stage, :reverse_run
  def initialize stage, reverse_run: nil
    @stage = stage
    @reverse_run = reverse_run
  end

  def to_hash
    { :class => self.class.to_s,
      :stage => self.stage.to_hash }
  end

  def reverse
    Interscript::Node::Rule::Run.new(stage,
      reverse_run: reverse_run.nil? ? nil : !reverse_run
    )
  end

  def inspect
    out = "run #{@stage.inspect}"
    out += ", reverse_run: #{@reverse_run.inspect}" unless reverse_run.nil?
    out
  end
end
