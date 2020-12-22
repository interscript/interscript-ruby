module Interscript::DSL

  def self.parse(filename)
    @document = Interscript::DSL::Document.new
    @document.instance_eval File.read(filename)
    @document.document
  end

end

require 'interscript/dsl/items'

require 'interscript/dsl/document'
require 'interscript/dsl/group'
require 'interscript/dsl/stage'
