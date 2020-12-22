module Interscript::DSL::Items

  %i{boundary not_word line_start line_end none space}.each do |sym|
    self.send(:define_method,sym) {
       Interscript::Node::Item.new(sym)}
  end
  
end