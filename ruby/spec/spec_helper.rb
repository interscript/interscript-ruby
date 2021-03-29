if ENV.include? "COVERAGE"
  require 'simplecov'
  SimpleCov.start do
    enable_coverage :branch
    primary_coverage :branch
  end
end
require "bundler/setup"
require "interscript"
require "interscript/compiler/ruby"
require "interscript/compiler/javascript"

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

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

  def each_compiler &block
    # Use ENV to select compilers?
    compilers = [
      Interscript::Interpreter,
      Interscript::Compiler::Ruby,
      Interscript::Compiler::Javascript
    ]

    compilers.each do |compiler|
      block.(compiler)
    end
  end
end

class Interscript::Node::Document
  def call(str, stage=:main, compiler=$compiler || Interscript::Interpreter)
    compiler.(self).(str, stage)
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
