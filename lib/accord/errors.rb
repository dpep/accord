# frozen_string_literal: true

module Accord
  # A first-class, structured description of a single parse or validation
  # failure — data, never a rendered message. Rendering (Rails JSON, GraphQL,
  # i18n, logs) is a separate concern.
  #
  #   Accord::Error.new(
  #     path: [:discount], code: :too_small, validator: :min, value: -5, expected: 0,
  #   )
  #
  # Always carries path, code, and (for validation failures) validator + value +
  # validator-specific metadata (expected, min, max, …). `field` defaults to the
  # last path segment. `**metadata` captures any validator-specific keys.
  class Error
    attr_reader :path, :code, :field, :validator, :value, :input, :metadata

    def initialize(path:, code:, field: nil, validator: nil, value: nil, input: nil, **metadata)
      @path = path
      @code = code
      @field = field.nil? ? path.last : field
      @validator = validator
      @value = value
      @input = input
      @metadata = metadata
    end

    # Structured data with nil-valued keys dropped — the minimal machine-readable
    # form (`{ path:, code: }`) up to the full validator error.
    def to_h
      { path:, field:, code:, validator:, value:, input:, **metadata }.compact
    end
    alias as_json to_h

    def ==(other)
      other.is_a?(Error) && to_h == other.to_h
    end
    alias eql? ==

    def hash
      to_h.hash
    end

    # The OpenAPI schema for one structured error (the shape of #to_h), and for
    # the default `{ errors: [ ... ] }` response body — so an API can document
    # its 422s from the same source that produces them.
    def self.openapi
      {
        type: "object",
        properties: {
          path: { type: "array", items: {} },
          field: { type: "string" },
          code: { type: "string" },
          validator: { type: "string" },
        },
        required: %i[path code],
      }
    end

    def self.openapi_response
      {
        type: "object",
        properties: { errors: { type: "array", items: openapi } },
        required: %i[errors],
      }
    end
  end

  # Base class for exceptions Accord raises.
  class Fault < StandardError; end

  # Raised by a type when a value cannot be coerced. Carries enough context
  # for a schema to build an Accord::Error describing what went wrong. In
  # strict mode this propagates; in permissive mode a schema catches it.
  class CoercionError < Fault
    attr_reader :code, :input

    def initialize(message = nil, code:, input:)
      @code = code
      @input = input
      super(message || code.to_s)
    end
  end

  # Raised (in strict mode) when a required field is absent.
  class MissingField < Fault
    attr_reader :field

    def initialize(field)
      @field = field
      super("#{field} is required")
    end
  end

  # Raised when input fails to satisfy a schema. Carries the parsed-but-invalid
  # schema instance so callers (e.g. Rails integration) can render its errors.
  class InvalidInput < Fault
    attr_reader :input

    def initialize(input)
      @input = input
      super("input did not satisfy the schema")
    end

    def errors
      input.errors
    end
  end
end
