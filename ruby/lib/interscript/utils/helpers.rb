module Interscript::Utils
  module Helpers
    def document name=nil, &block
      $example_id ||= 0
      $example_id += 1
      name ||= "example-#{$example_id}"

      Interscript::DSL::Document.new(name, &block).node.tap do |i|
        $documents ||= {}
        $documents[name] = i
      end
    end

    def stage &block
      document {
        stage(&block)
      }
    end
  end
end

class Interscript::Node::Document
  def call(str, stage=:main, compiler=$compiler || Interscript::Interpreter, **kwargs)
    compiler.(self).(str, stage, **kwargs)
  end
end

module Interscript::DSL
  class << self
    alias original_parse parse
    def parse(map_name)
      if $documents && $documents[map_name]
        $documents[map_name]
      else
        original_parse(map_name)
      end
    end
  end
end