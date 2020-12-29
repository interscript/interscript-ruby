module Interscript::DSL

  def self.parse(filename)
    @obj = Interscript::DSL::Document.new
    @obj.instance_eval File.read(filename), filename, 0
    @obj.node.to_hash
  end

end

require 'interscript/dsl/items'

require 'interscript/dsl/document'
require 'interscript/dsl/group'
require 'interscript/dsl/stage'
require 'interscript/dsl/metadata'
require 'interscript/dsl/tests'
