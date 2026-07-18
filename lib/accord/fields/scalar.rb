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
      schema[:description] = description if description
      schema[:example] = example unless example.nil?
      schema
    end

    private

    def coerce_present(raw, strict:, path:)
      Result.ok(type.cast(raw, strict:))
    rescue CoercionError => e
      raise if strict

      Result.failed(error(path, e.code, input: e.input))
    end
  end
end
