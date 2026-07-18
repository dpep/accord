# frozen_string_literal: true

require_relative "errors"

module Accord
  # A declared field on a schema: a name bound to a kind of value plus options
  # (required, default, description, example). This base class owns the
  # presence/default/required policy shared by every field kind; subclasses
  # (ScalarField, ObjectField, ArrayField) implement #coerce_present to turn a
  # present raw value into a coerced value plus any nested errors.
  class Field
    # The outcome of resolving one field: its coerced value and the structured
    # errors produced beneath it. Errors accumulate rather than raise so a
    # permissive parse can report every problem at once.
    Result = Struct.new(:value, :errors) do
      def self.ok(value) = new(value, [])
      def self.failed(error) = new(nil, [error])
    end

    attr_reader :name, :default, :description, :example

    def initialize(name:, required: false, default: nil, description: nil, example: nil)
      @name = name
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
      return [false, nil] unless input.respond_to?(:key?)
      return [true, input[name]] if input.key?(name)
      return [true, input[name.to_s]] if input.key?(name.to_s)

      [false, nil]
    end

    # Resolve this field against raw input. Applies presence/default/required
    # policy, then delegates a present value to #coerce_present. In strict mode
    # failures raise; otherwise they are collected into the Result.
    def resolve(input, strict:, path:)
      present, raw = read(input)

      if !present || raw.nil?
        return Result.ok(resolve_default) if has_default?
        raise MissingField, name if required? && strict
        return Result.failed(error(path, :required)) if required?

        return Result.ok(nil)
      end

      coerce_present(raw, strict:, path:)
    end

    def openapi
      raise NotImplementedError, "#{self.class} must implement #openapi"
    end

    private

    # @abstract Coerce a present (non-nil) raw value into a Result.
    def coerce_present(_raw, strict:, path:)
      raise NotImplementedError, "#{self.class} must implement #coerce_present"
    end

    def resolve_default
      default.respond_to?(:call) ? default.call : default
    end

    # Build an Accord::Error located at this field (path + this field's name).
    def error(path, code, input: nil)
      Error.new(field: name, path: path + [name], code:, input:)
    end

    # Parse a raw value through a sub-schema at the given (already-built) path.
    # Returns [value, errors]. Shared by ObjectField and ArrayField.
    def parse_object(schema, raw, strict:, path:)
      unless raw.respond_to?(:key?)
        raise CoercionError.new(code: :invalid_object, input: raw) if strict

        return [nil, [Error.new(field: name, path:, code: :invalid_object, input: raw)]]
      end

      sub = schema.parse(raw, strict:, path:)
      [sub, sub.errors]
    end
  end
end
