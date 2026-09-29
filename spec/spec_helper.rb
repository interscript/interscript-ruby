if ENV.include? "COVERAGE"
  require "simplecov"
  SimpleCov.start do
    enable_coverage :branch
    primary_coverage :branch
  end
end
require "bundler/setup"
require "interscript"
require "interscript/compiler/ruby"
require "interscript/compiler/javascript" unless ENV["SKIP_JS"]
require "interscript/compiler/python" unless ENV["SKIP_PYTHON"]
require "interscript/utils/helpers"

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  # dsl_stage_spec sets the $compiler global per example; without a
  # reset it leaks into every file that runs afterwards, silently
  # rerouting suites that never opted into a specific compiler.
  # standard:disable Style/GlobalVars (deliberate $DEBUG / -d-flag debug idiom)
  config.before(:example) do
    $compiler = nil
  end
  # standard:enable Style/GlobalVars

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  include Interscript::Utils::Helpers

  # Legacy .imp corpus enumeration. Suites written for the compiled-DSL
  # pipeline keep their historical scope until each gains ISC-era
  # conformance (naming rules, metadata schema, per-map timeouts).
  def legacy_maps(select: "*")
    Interscript.maps(basename: false, select: select)
      .select { |f| f.end_with?(".imp") }
      .map { |f| File.basename(f, ".*") }
  end

  def each_compiler &block
    compilers = []
    compilers << Interscript::Interpreter
    compilers << Interscript::Compiler::Ruby
    compilers << Interscript::Compiler::Javascript unless ENV["SKIP_JS"]
    compilers << Interscript::Compiler::Python unless ENV["SKIP_PYTHON"]

    compilers.each do |compiler|
      block.call(compiler)
    end
  end
end
