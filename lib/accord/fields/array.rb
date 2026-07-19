# frozen_string_literal: true

require_relative "../field"

module Accord
  # A field holding a list of nested schemas. Each element is parsed through the
  # element schema; errors carry the element's index in their path, e.g.
  # [:employees, 2, :salary].
  #
  #   array :employees, Employee
  class ArrayField < Field
    attr_reader :schema

    def initialize(schema:, **opts)
      super(**opts)
      @schema = schema
    end

    def openapi
      { type: "array", items: openapi_ref(schema) }
    end

    def dump(value)
      value&.map(&:dump)
    end

    def nested_schema
      schema
    end

    def rbs
      "Array[#{schema.name || "untyped"}]"
    end

    def sorbet
      "T::Array[#{schema.name || "T.untyped"}]"
    end

    def graphql_ref
      element = schema.graphql_input_name || raise(ArgumentError, "cannot generate GraphQL for an anonymous nested schema")
      "[#{element}!]"
    end

    private

    def coerce_present(raw, strict:, path:)
      unless raw.is_a?(::Array)
        raise CoercionError.new(code: :invalid_array, input: raw) if strict

        return Result.failed(error(path, :invalid_array, input: raw))
      end

      values = []
      errors = []
      raw.each_with_index do |element, index|
        value, element_errors = parse_object(schema, element, strict:, path: path + [name, index])
        values << value
        errors.concat(element_errors)
      end

      Result.new(values, errors)
    end
  end
end
