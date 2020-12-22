module Interscript::DSL::Stage

  %i{boundary not_word line_start line_end none space}.each do |sym|
    self.class.send(:define_method,sym) {
       Interscript::Node::Item.new(sym)}
  end

  #doesn't do anything yet
  def map(*args)
    {}
  end
  def run(*args)
    nil
  end

  def parallel(&block)
    puts "parallel(#{chars.inspect}) from #{self.inspect}" if $DEBUG
    self.children << Interscript::Node::Group::Parallel.new(&block)
  end

end