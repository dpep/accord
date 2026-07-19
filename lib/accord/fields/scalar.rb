# frozen_string_literal: true

require_relative "../field"

module Accord
  # A field backed by a scalar Type (string, boolean, date, currency). Coercion
  # is delegated to the type; a failure becomes a collected error (permissive)
  # or propagates (strict).
  class ScalarField < Field
    attr_reader :type

    def initialize(type:, **opts)
      super(**opts)
      @type = type
    end

    def openapi
      schema = type.openapi.dup
      validators.each { |validator| schema.merge!(validator.openapi) }
      schema[:description] = description if description
      schema[:example] = example unless example.nil?
      schema
    end

    def rbs
      type.rbs
    end

    def sorbet
      type.sorbet
    end

    private

    def coerce_present(raw, strict:, path:)
      value = type.cast(raw, strict:)
      observe_permissive_coercion(raw, value, path) if !strict && Accord.observe_coercions?
      Result.ok(value)
    rescue CoercionError => e
      raise if strict

      Result.failed(error(path, e.code, input: e.input))
    end

    # If the value only coerced because permissive rules accepted input that
    # strict rules would reject, emit accord.parse.coerced — carrying the raw
    # input (the "variant" seen) and the canonical value. When a field stops
    # emitting these, it's safe to make it strict.
    def observe_permissive_coercion(raw, value, path)
      type.cast(raw, strict: true)
    rescue CoercionError
      Accord.instrument(:coerced, field: name, path: path + [name], input: raw, value:, type: type.type_name)
    end
  end
end
