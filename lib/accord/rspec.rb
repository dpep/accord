# frozen_string_literal: true

# Opt-in RSpec matchers for testing Accord schemas and responses:
#   require "accord/rspec"   # in spec_helper / rails_helper
#
#   expect(response.parsed_body).to conform_to(EmployeeView)
#   expect(CreateEmployee.parse(params)).to have_error(:not_positive).at(:salary)
require "rspec/expectations"

# Assert a value satisfies a schema — parses it and checks it's valid. The
# response-contract matcher (`conform_to(EmployeeView)`), and a readable way to
# assert acceptance without a separate `accept` matcher.
RSpec::Matchers.define :conform_to do |schema|
  match do |actual|
    @result = schema.parse(actual)
    @result.valid?
  end

  failure_message do |actual|
    problems = @result.errors.map { |e| "#{e.path.join(".")}: #{e.code}" }.join(", ")
    "expected #{actual.inspect} to conform to #{schema}, but: #{problems}"
  end

  failure_message_when_negated do |actual|
    "expected #{actual.inspect} not to conform to #{schema}, but it did"
  end
end

# Assert a parsed result carries a specific structured error, without digging
# through `.errors.map(&:to_h)`. Chain `.at` (a varargs path) and `.with`
# (validator metadata) to narrow it:
#   have_error(:required).at(:name)
#   have_error(:out_of_range).at(:employees, 2, :age).with(min: 18, max: 120)
RSpec::Matchers.define :have_error do |code|
  chain(:at) { |*path| @path = path }
  chain(:with) { |metadata| @metadata = metadata }

  match do |result|
    result.errors.any? do |error|
      error.code == code &&
        (@path.nil? || error.path == @path) &&
        (@metadata.nil? || @metadata.all? { |key, value| error.metadata[key] == value })
    end
  end

  failure_message do |result|
    want = +"an error #{code.inspect}"
    want << " at #{@path.inspect}" if @path
    want << " with #{@metadata.inspect}" if @metadata
    had = result.errors.map { |e| { path: e.path, code: e.code, **e.metadata } }
    "expected #{want}, but the errors were: #{had.inspect}"
  end
end
