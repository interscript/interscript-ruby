
class Interscript::Node
  def initialize
    raise NotImplementedError, "You can't construct a Node directly"
  end

  def to_hash
    { :class => self.class.to_s,
      :question => "is something missing?"
    }
  end
end


require "interscript/node/group"
require "interscript/node/document"

require "interscript/node/metadata"
require 'interscript/node/alias_def'
require 'interscript/node/dependency'
require 'interscript/node/tests'

require "interscript/node/stage"
require "interscript/node/rule"
require "interscript/node/item"
