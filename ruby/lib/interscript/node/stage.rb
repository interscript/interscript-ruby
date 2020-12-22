class Interscript::Node::Stage < Interscript::Node::Group::Sequential
  include Interscript::DSL::Stage

  attr_accessor :children

  def initialize *args, **kargs, &block
    puts "Interscript::Node::Stage.new (args = #{
      args.inspect})" if $DEBUG

    self.children = []

    if block_given?
      self.instance_eval(&block)
    end

    #self
  end


  def to_hash
    {:class => self.class.to_s,
      :children => @children.map{|x| x.to_hash}}
  end


end
