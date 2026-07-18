# frozen_string_literal: true

require_relative "accord/version"
require_relative "accord/errors"
require_relative "accord/configuration"
require_relative "accord/type"
require_relative "accord/types/string"
require_relative "accord/types/boolean"
require_relative "accord/types/date"
require_relative "accord/types/decimal"
require_relative "accord/types/currency"
require_relative "accord/types/duration"
require_relative "accord/field"
require_relative "accord/fields/scalar"
require_relative "accord/fields/object"
require_relative "accord/fields/array"
require_relative "accord/validation"
require_relative "accord/schema"

# Accord — executable API contracts for Ruby.
#
# A schema declares the accepted input for an API boundary: it coerces
# untrusted values into typed Ruby objects, validates them, collects
# structured errors, and documents the contract.
module Accord
  class << self
    # Library configuration (e.g. the default parse mode). See Configuration.
    def config
      @config ||= Configuration.new
    end

    def configure
      yield config
    end

    # Optional logger used by permissive standalone type coercion to record
    # dropped values.
    attr_accessor :logger

    # Optional notifier for permissive-parse events. Any object responding to
    # `instrument(event, **payload)`. `require "accord/rails"` wires this to
    # ActiveSupport::Notifications; left nil, instrumentation is a no-op so the
    # core gem carries no Rails/ActiveSupport dependency.
    attr_accessor :notifier

    # Emit a permissive-parse event, e.g. "accord.parse.invalid_currency".
    # Called whenever a schema tolerates and records an error rather than
    # raising — so only ever in non-strict mode.
    def instrument(code, **payload)
      notifier&.instrument("accord.parse.#{code}", **payload)
    end
  end
end
