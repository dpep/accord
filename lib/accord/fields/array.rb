# frozen_string_literal: true

require_relative "../field"

module Accord
  # A field holding a list. Its element is either a nested Schema (a list of
  # objects) or a scalar Type (a list of strings, uuids, ...). Each element is
  # parsed at its index, so errors carry it: [:employees, 2, :salary] or
  # [:tags, 1].
  #
  #   array :employees, Employee     # list of nested schemas
  #   array :tags, :string           # list of scalars
  class ArrayField < Field
    attr_reader :element

    def initialize(element:, **opts)
      super(**opts)
      @element = element
    end

    # True when the element is a nested schema (vs a scalar type).
    def schema_element?
      element.is_a?(::Class) && element < Schema
    end

    def openapi
      { type: "array", items: schema_element? ? openapi_ref(element) : element.openapi }
    end

    def dump(value)
      return if value.nil?

      schema_element? ? value.map(&:dump) : value.map { |item| element.dump(item) }
    end

    # Only a schema element is an OpenAPI/GraphQL component; a scalar type is inline.
    def nested_schema
      element if schema_element?
    end

    def rbs
      "Array[#{schema_element? ? (element.name || "untyped") : element.rbs}]"
    end

    def sorbet
      "T::Array[#{schema_element? ? (element.name || "T.untyped") : element.sorbet}]"
    end

    def graphql_ref
      inner =
        if schema_element?
          element.graphql_input_name || raise(ArgumentError, "cannot generate GraphQL for an anonymous nested schema")
        else
          element.graphql
        end
      "[#{inner}!]"
    end

    private

    def coerce_present(raw, strict:, path:)
      unless raw.is_a?(::Array)
        raise CoercionError.new(code: :invalid_array, input: raw) if strict

        return Result.failed(error(path, :invalid_array, input: raw))
      end

      values = []
      errors = []
      raw.each_with_index do |item, index|
        value, item_errors = coerce_element(item, strict:, path: path + [name, index])
        values << value
        errors.concat(item_errors)
      end

      Result.new(values, errors)
    end

    # Parse one element — through the sub-schema (objects) or the type (scalars).
    def coerce_element(item, strict:, path:)
      return parse_object(element, item, strict:, path:) if schema_element?

      [element.cast(item, strict:), []]
    rescue CoercionError => e
      raise if strict

      [nil, [build_error(path:, code: e.code, input: e.input)]]
    end
  end
end
