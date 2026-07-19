# frozen_string_literal: true

require_relative "accord/version"
require_relative "accord/errors"
require_relative "accord/configuration"
require_relative "accord/type"
require_relative "accord/types"
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

    # Emit a standard permissive-parse event — an error the schema tolerated
    # (`accord.parse.<code>`) or a value it rounded. Gated by
    # `config.notifications` (default on) and a no-op without a notifier.
    def notify(code, **payload)
      emit("accord.parse.#{code}", **payload) if config.notifications
    end

    # Emit `accord.parse.coerced` — a value that only parsed because permissive
    # rules accepted input strict rules would reject. Gated by
    # `config.observe_coercions` (default off).
    def notify_coerced(**payload)
      emit("accord.parse.coerced", **payload) if config.observe_coercions
    end

    # Whether to run the (opt-in, costs a strict re-check per loose field)
    # coercion-observability path. Only active when a notifier is listening.
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

    private

    def emit(event, **payload)
      notifier&.instrument(event, **payload)
    end
  end
end
