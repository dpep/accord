# frozen_string_literal: true

require_relative "../field"

module Accord
  # A field holding a nested schema. The coerced value is a parsed sub-schema
  # instance (so `input.address.city` works), and any errors beneath it bubble
  # up with their paths prefixed by this field's name.
  #
  #   object :address, Address
  class ObjectField < Field
    attr_reader :schema

    def initialize(schema:, **opts)
      super(**opts)
      @schema = schema
    end

    def openapi
      openapi_ref(schema)
    end

    def dump(value)
      value&.dump
    end

    def nested_schema
      schema
    end

    def rbs
      schema.name || "untyped"
    end

    def sorbet
      schema.name || "T.untyped"
    end

    private

    def coerce_present(raw, strict:, path:)
      value, errors = parse_object(schema, raw, strict:, path: path + [name])
      Result.new(value, errors)
    end
  end
end
