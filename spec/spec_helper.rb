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
require "interscript/compiler/javascript" unless ENV["SKIP_JS"]
require "interscript/utils/helpers"

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  include Interscript::Utils::Helpers

  def each_compiler &block
    compilers = []
    compilers << Interscript::Interpreter
    compilers << Interscript::Compiler::Ruby
    compilers << Interscript::Compiler::Javascript unless ENV["SKIP_JS"]

    compilers.each do |compiler|
      block.(compiler)
    end
  end
end
