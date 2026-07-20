require "debug"
require "rspec"
require "rspec/matchers/fail_matchers"
require "simplecov"

SimpleCov.start do
  add_filter "/spec/"
end

if ENV["CI"] == "true" || ENV["CODECOV_TOKEN"]
  require "simplecov_json_formatter"
  SimpleCov.formatter = SimpleCov::Formatter::JSONFormatter
end

require "accord"
require "accord/rspec"   # the shipped matchers, dogfooded across the suite

RSpec.configure do |config|
  # allow "fit" examples
  config.filter_run_when_matching :focus

  # expect { ... }.to fail
  config.include RSpec::Matchers::FailMatchers

  config.expect_with(:rspec) { |c| c.syntax = :expect }
  config.disable_monkey_patching!
  # ...but keep the bare top-level `describe` (disable_monkey_patching! turns off
  # the object-space `should`/stub patches AND the global DSL; re-enable just the
  # DSL so specs read `describe`, not `describe`).
  config.expose_dsl_globally = true
  config.order = :random
  Kernel.srand config.seed
end
