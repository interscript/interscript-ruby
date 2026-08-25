# frozen_string_literal: true

require "rspec"
require "interscript/isc"

RSpec.configure do |config|
  config.example_status_persistence_file_path = ".rspec_status_isc"
  config.disable_monkey_patching!
  config.color = true
  config.formatter = :documentation if config.files_to_run.one?
end
