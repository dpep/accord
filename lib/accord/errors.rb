# frozen_string_literal: true

module Accord
  # A first-class, structured description of a single parse or validation
  # failure. These are what a schema collects and what a controller renders.
  #
  #   Accord::Error.new(
  #     path: [:employees, 2, :salary],
  #     code: :invalid_currency,
  #     input: "$abc",
  #   )
  class Error
    attr_reader :field, :path, :code, :message, :input, :value

    def initialize(field:, path:, code:, message: nil, input: nil, value: nil)
      @field = field
      @path = path
      @code = code
      @message = message || code.to_s
      @input = input
      @value = value
    end

    def to_h
      {
        field:,
        path:,
        code:,
        message:,
        input:,
        value:,
      }
    end
    alias as_json to_h

    def ==(other)
      other.is_a?(Error) && to_h == other.to_h
    end
    alias eql? ==

    def hash
      to_h.hash
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
end
