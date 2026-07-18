# frozen_string_literal: true

require_relative "errors"
require_relative "field"
require_relative "fields/scalar"
require_relative "fields/object"
require_relative "fields/array"
require_relative "validation"
require_relative "types/string"
require_relative "types/boolean"
require_relative "types/date"
require_relative "types/decimal"
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

      def decimal(name, scale: Types::Decimal::DEFAULT_SCALE, round: false, **opts)
        field(name, Types::Decimal.new(scale:, round:), **opts)
      end

      def currency(name, scale: 2, round: false, **opts)
        field(name, Types::Currency.new(scale:, round:), **opts)
      end

      # A nested schema. The parsed value is a sub-schema instance.
      #   object :address, Address
      def object(name, schema, **opts)
        register(ObjectField.new(name:, schema:, **opts))
      end

      # A list of nested schemas. Each element is parsed through `schema`.
      #   array :employees, Employee
      def array(name, schema, **opts)
        register(ArrayField.new(name:, schema:, **opts))
      end

      # Declare a scalar field backed by a Type. Public so custom types can be
      # registered directly.
      def field(name, type, **opts)
        register(ScalarField.new(name:, type:, **opts))
      end

      # Register a field and define its reader.
      def register(field)
        fields[field.name] = field
        define_method(field.name) { @values[field.name] }
        field.name
      end

      def validate(field = nil, &block)
        validations << Validation.new(field, block)
        self
      end

      # Parse untrusted input into a typed schema instance.
      #
      # Non-strict (the default, configurable via Accord.config.strict) collects
      # errors and normalizes legacy input. Strict raises on the first coercion
      # failure — for trusted callers. A per-call `strict:` overrides the config.
      def parse(input, strict: Accord.config.strict, path: [])
        new._parse(input || {}, strict:, path:)
      end

      # Parse and raise Accord::InvalidInput unless the result is valid — the
      # entry point for callers that want the typed input or a failure, with no
      # `.valid?` check (e.g. Rails controllers).
      def parse!(input, **options)
        parse(input, **options).tap do |result|
          raise InvalidInput, result unless result.valid?
        end
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
      path = @path + [field].compact
      Accord.instrument(code, field:, path:, input: nil)
      @errors << Error.new(field:, path:, code:, value: field && @values[field])
    end

    # @api private — orchestrates coercion + validation. Public so
    # Schema.parse can drive a freshly-allocated instance.
    def _parse(input, strict:, path:)
      @path = path

      self.class.fields.each_value do |field|
        result = field.resolve(input, strict:, path:)
        @values[field.name] = result.value
        @errors.concat(result.errors)
      end

      run_validations
      self
    end

    private

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
