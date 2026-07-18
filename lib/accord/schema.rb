# frozen_string_literal: true

require_relative "errors"
require_relative "field"
require_relative "validation"
require_relative "types/string"
require_relative "types/boolean"
require_relative "types/date"
require_relative "types/currency"

module Accord
  # A schema is the source of truth for an API boundary. The class declares the
  # contract (fields + validations); an instance IS the parsed, typed result —
  # accessors return coerced values directly, with no wrappers.
  #
  #   class CreateEmployee < Accord::Schema
  #     string :name, required: true
  #     boolean :active, default: true
  #     currency :salary
  #
  #     validate(:salary) { |salary| error(:must_be_positive) if salary.negative? }
  #   end
  #
  #   input = CreateEmployee.parse(params)
  #   input.valid?   # => true / false
  #   input.name     # => "Ada"
  #   input.errors   # => [Accord::Error, ...]
  class Schema
    class << self
      def fields
        @fields ||= {}
      end

      def validations
        @validations ||= []
      end

      # Subclasses inherit a copy of declared fields/validations so extending a
      # schema doesn't mutate its parent.
      def inherited(subclass)
        super
        subclass.instance_variable_set(:@fields, fields.dup)
        subclass.instance_variable_set(:@validations, validations.dup)
      end

      def string(name, **opts)
        field(name, Types::String.new, **opts)
      end

      def boolean(name, **opts)
        field(name, Types::Boolean.new, **opts)
      end

      def date(name, formats: [], **opts)
        field(name, Types::Date.new(formats:), **opts)
      end

      def currency(name, **opts)
        field(name, Types::Currency.new, **opts)
      end

      # Register a field and define its reader.
      def field(name, type, **opts)
        fields[name] = Field.new(name:, type:, **opts)
        define_method(name) { @values[name] }
        name
      end

      def validate(field = nil, &block)
        validations << Validation.new(field, block)
        self
      end

      # Parse untrusted input into a typed schema instance.
      #
      # strict: false (default) collects errors and normalizes legacy input.
      # strict: true raises on the first coercion failure — for trusted callers.
      def parse(input, strict: false, path: [])
        new._parse(input || {}, strict:, path:)
      end
    end

    def initialize
      @values = {}
      @errors = []
    end

    attr_reader :errors

    def valid?
      errors.empty?
    end

    def to_h
      @values.dup
    end

    def [](name)
      @values[name]
    end

    # Called during validation blocks to record a structured error.
    #   error(:code)                  # field-scoped validation
    #   error(:code, field: :salary)  # explicit field
    def error(code, field: @current_field)
      @errors << Error.new(
        field:,
        path: @path + [field].compact,
        code:,
        value: field && @values[field],
      )
    end

    # @api private — orchestrates coercion + validation. Public so
    # Schema.parse can drive a freshly-allocated instance.
    def _parse(input, strict:, path:)
      @path = path

      self.class.fields.each_value do |field|
        @values[field.name] = field.coerce(input, strict:)
      rescue CoercionError => e
        raise if strict

        record_coercion_error(field, e)
      rescue MissingField
        raise if strict

        record_missing(field)
      end

      run_validations
      self
    end

    private

    def record_coercion_error(field, error)
      @values[field.name] = nil
      @errors << Error.new(
        field: field.name,
        path: @path + [field.name],
        code: error.code,
        input: error.input,
      )
    end

    def record_missing(field)
      @errors << Error.new(
        field: field.name,
        path: @path + [field.name],
        code: :required,
      )
    end

    # Validations run in declaration order, after all fields are coerced.
    # A field-scoped validation is skipped when its field is absent/nil or
    # already failed coercion — the rule can assume a usable value.
    def run_validations
      self.class.validations.each do |validation|
        if validation.scoped?
          next if failed?(validation.field) || @values[validation.field].nil?

          @current_field = validation.field
          instance_exec(@values[validation.field], &validation.block)
        else
          @current_field = nil
          instance_exec(&validation.block)
        end
      end
      @current_field = nil
    end

    def failed?(field)
      @errors.any? { |e| e.field == field }
    end
  end
end
