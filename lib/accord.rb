# frozen_string_literal: true

require_relative "accord/version"
require_relative "accord/errors"
require_relative "accord/configuration"
require_relative "accord/type"
require_relative "accord/types/string"
require_relative "accord/types/uuid"
require_relative "accord/types/iso_currency"
require_relative "accord/types/boolean"
require_relative "accord/types/integer"
require_relative "accord/types/date"
require_relative "accord/types/decimal"
require_relative "accord/types/currency"
require_relative "accord/types/duration"
require_relative "accord/types/percentage"
require_relative "accord/validators"
require_relative "accord/field"
require_relative "accord/fields/scalar"
require_relative "accord/fields/object"
require_relative "accord/fields/array"
require_relative "accord/fields/money"
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

    # Whether to emit `accord.parse.coerced` when a permissive parse accepts
    # input that strict rules would reject — the signal for narrowing permissive
    # scope toward strict. Opt-in (it costs a strict re-check per loose field)
    # and only active when a notifier is listening.
    def observe_coercions?
      config.observe_coercions && !notifier.nil?
    end

    # Merge the OpenAPI component schemas of several schemas (each plus its
    # nested schemas) into one map — for an OpenAPI `components: { schemas: ... }`
    # section. See docs/openapi.md.
    def openapi_schemas(*schemas)
      schemas.each_with_object({}) { |schema, into| schema.openapi_schemas(into) }
    end

    # Lazily load the optional `money` gem, which backs the money and
    # iso_currency types. Raises a helpful error if it isn't installed.
    def require_money!
      require "money"
    rescue LoadError
      raise Fault, "Accord's `money` and `iso_currency` types require the money gem. " \
                   "Add `gem \"money\"` to your Gemfile."
    end
  end
end
