# frozen_string_literal: true

require_relative "errors"
require_relative "field"
require_relative "fields/scalar"
require_relative "fields/object"
require_relative "fields/array"
require_relative "fields/money"
require_relative "types/string"
require_relative "types/uuid"
require_relative "types/iso_currency"
require_relative "types/boolean"
require_relative "types/integer"
require_relative "types/date"
require_relative "types/decimal"
require_relative "types/currency"
require_relative "types/duration"
require_relative "types/percentage"

module Accord
  # A schema is the source of truth for an API boundary. The class declares the
  # contract (fields + declarative validators); an instance IS the parsed, typed
  # result — accessors return coerced values directly, with no wrappers.
  #
  #   class CreateEmployee < Accord::Schema
  #     string :name, required: true
  #     boolean :active, default: true
  #     currency :salary do
  #       positive
  #     end
  #   end
  #
  #   input = CreateEmployee.parse(params)
  #   input.valid?   # => true / false
  #   input.name     # => "Ada"
  #   input.errors   # => [Accord::Error, ...]
  #
  # Validation is declared in field blocks — see Field::Configurator.
  class Schema
    class << self
      def fields
        @fields ||= {}
      end

      # Subclasses inherit a copy of declared fields so extending a schema
      # doesn't mutate its parent.
      def inherited(subclass)
        super
        subclass.instance_variable_set(:@fields, fields.dup)
      end

      # Every scalar DSL method takes positional validator flags after the name
      # (no-arg validators like :required, :positive), keyword type options, and
      # an optional field block:  string :name, :required do length 1..100 end
      def string(name, *flags, **opts, &block)
        field(name, Types::String.new, *flags, **opts, &block)
      end

      def uuid(name, *flags, version: nil, **opts, &block)
        field(name, Types::UUID.new(version:), *flags, **opts, &block)
      end

      def iso_currency(name, *flags, **opts, &block)
        field(name, Types::ISOCurrency.new, *flags, **opts, &block)
      end

      def boolean(name, *flags, **opts, &block)
        field(name, Types::Boolean.new, *flags, **opts, &block)
      end

      def integer(name, *flags, **opts, &block)
        field(name, Types::Integer.new, *flags, **opts, &block)
      end

      def date(name, *flags, formats: [], **opts, &block)
        field(name, Types::Date.new(formats:), *flags, **opts, &block)
      end

      def decimal(name, *flags, scale: Types::Decimal::DEFAULT_SCALE, round: false, **opts, &block)
        field(name, Types::Decimal.new(scale:, round:), *flags, **opts, &block)
      end

      def currency(name, *flags, scale: 2, round: false, **opts, &block)
        field(name, Types::Currency.new(scale:, round:), *flags, **opts, &block)
      end

      def duration(name, *flags, unit: :hours, scale: 2, round: false, **opts, &block)
        field(name, Types::Duration.new(unit:, scale:, round:), *flags, **opts, &block)
      end

      def percentage(name, *flags, scale: 2, round: false, **opts, &block)
        field(name, Types::Percentage.new(scale:, round:), *flags, **opts, &block)
      end

      # A nested schema. The parsed value is a sub-schema instance.
      #   object :address, Address
      def object(name, schema, *flags, **opts, &block)
        register_field(ObjectField.new(name:, schema:, **opts), flags, &block)
      end

      # A list of nested schemas. Each element is parsed through `schema`.
      #   array :employees, Employee
      def array(name, schema, *flags, **opts, &block)
        register_field(ArrayField.new(name:, schema:, **opts), flags, &block)
      end

      # An amount + currency parsed into a money-gem Money value.
      #   money :salary
      def money(name, *flags, **opts, &block)
        register_field(MoneyField.new(name:, **opts), flags, &block)
      end

      # Declare a scalar field backed by a Type. Public so custom types can be
      # registered directly. Positional flags and a block configure validators.
      def field(name, type, *flags, **opts, &block)
        register_field(ScalarField.new(name:, type:, **opts), flags, &block)
      end

      # Attach positional validator flags and a field block, then register.
      def register_field(field, flags, &block)
        flags.each { |flag| field.add_validator(Validators.build(flag)) }
        field.configure(&block)
        register(field)
      end

      # Register a field and define its reader.
      def register(field)
        fields[field.name] = field
        define_method(field.name) { @values[field.name] }
        field.name
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

      # Project this schema into an RBS class declaration, giving typed reader
      # signatures so `input.salary` is known to editors, Sorbet, and Steep — no
      # runtime dependency, just generated signatures. Required and defaulted
      # fields are non-nilable; optional fields are nilable (the valid-shape
      # contract). Nested schemas are referenced by class name.
      def rbs(class_name: name)
        raise ArgumentError, "cannot generate RBS for an anonymous schema — pass class_name:" if class_name.nil?

        signatures = fields.each_value.map do |field|
          "  def #{field.name}: () -> #{field.rbs_return}"
        end

        ["class #{class_name} < Accord::Schema", *signatures, "end"].join("\n")
      end

      # Project this schema into a Sorbet RBI class declaration — the RBI sibling
      # of #rbs, for Sorbet-typed codebases. Prefer the bundled Tapioca DSL
      # compiler (auto-discovered by `tapioca dsl`) for Sorbet projects; this is
      # the manual/standalone form.
      def rbi(class_name: name)
        raise ArgumentError, "cannot generate RBI for an anonymous schema — pass class_name:" if class_name.nil?

        methods = fields.each_value.map do |field|
          "  sig { returns(#{field.sorbet_return}) }\n  def #{field.name}; end"
        end

        ["class #{class_name} < Accord::Schema", methods.join("\n\n"), "end"].join("\n")
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

    # @api private — resolves every field (coerce → validate) and aggregates the
    # errors. Public so Schema.parse can drive a freshly-allocated instance.
    def _parse(input, strict:, path:)
      self.class.fields.each_value do |field|
        result = field.resolve(input, strict:, path:)
        @values[field.name] = result.value
        @errors.concat(result.errors)
      end

      self
    end
  end
end
