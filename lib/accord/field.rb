# frozen_string_literal: true

module Accord
  # A declared field on a schema: a name bound to a type plus options
  # (required, default, description, example). The field pairs the coercion
  # logic (its type) with the presence/default policy; the schema orchestrates
  # error collection around it.
  class Field
    attr_reader :name, :type, :default, :description, :example

    def initialize(name:, type:, required: false, default: nil, description: nil, example: nil)
      @name = name
      @type = type
      @required = required
      @default = default
      @description = description
      @example = example
      @has_default = !default.nil?
    end

    def required?
      @required
    end

    def has_default?
      @has_default
    end

    # Read this field's raw value from an input hash, tolerating string or
    # symbol keys. Returns [present?, raw_value].
    def read(input)
      return [true, input[name]] if input.key?(name)
      return [true, input[name.to_s]] if input.key?(name.to_s)

      [false, nil]
    end

    # Coerce this field's value out of the raw input. Returns the canonical
    # value, or raises CoercionError / MissingField for the schema to handle.
    def coerce(input, strict:)
      present, raw = read(input)

      if !present || raw.nil?
        return resolve_default if has_default?
        raise MissingField, name if required?

        return
      end

      type.cast(raw, strict:)
    end

    def openapi
      schema = type.openapi.dup
      schema[:description] = description if description
      schema[:example] = example unless example.nil?
      schema
    end

    private

    def resolve_default
      default.respond_to?(:call) ? default.call : default
    end
  end
end
