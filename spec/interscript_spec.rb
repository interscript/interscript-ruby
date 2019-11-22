# frozen_string_literal: true

require "diffy"

RSpec.describe Interscript do
  it "test all systems" do
    match_system = ENV["TRANSLIT_SYSTEM"] || "*"
    results = Dir["maps/#{match_system}.yaml"].reduce({}) do |sysresults, system_file|
      puts "Testing system " + system_file + " ..."
      system = YAML.load_file system_file
      system_name = File.basename(system_file, ".yaml")

      tests = system["tests"]&.reduce([]) do |testresults, test|
        result = Interscript.transliterate system_name, test["source"]
        diff = Diffy::Diff.new test["expected"], result
        testresults << { expected: test["expected"], got: result, diff: diff } unless diff.to_s.empty?
        testresults
      end

      sysresults[system_name] = tests unless tests.nil? || tests.empty?
      sysresults
    end

    unless results.empty?
      puts
      warn "Failures:"
      results.each do |name, tests|
        puts
        warn "  Fail system: #{name}"
        tests.each do |test|
          warn "    expected: #{test[:expected]}"
          warn "         got: #{test[:got]}"
          if test[:expected].lines.count > 2
            puts
            warn "Diff:"
            warn test[:diff]
          end
        end
      end
    end

    expect(results).to be_empty
  end
end
