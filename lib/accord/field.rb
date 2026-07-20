# frozen_string_literal: true

require_relative "errors"
require_relative "validators"

module Accord
  # A declared field on a schema: a name bound to a kind of value plus options
  # (required, default, description, example) and declarative validators. This
  # base class owns the presence/default/required policy and the validation
  # lifecycle shared by every field kind; subclasses (ScalarField, ObjectField,
  # ArrayField) implement #coerce_present to turn a present raw value into a
  # coerced value plus any nested errors.
  class Field
    # The outcome of resolving one field: its coerced value and the structured
    # errors produced beneath it. Errors accumulate rather than raise so a
    # permissive parse can report every problem at once.
    Result = Struct.new(:value, :errors) do
      def self.ok(value) = new(value, [])
      def self.failed(error) = new(nil, [error])
    end

    attr_reader :name, :default, :description, :example, :validators

    def initialize(name:, required: false, default: nil, description: nil, example: nil)
      @name = name
      @default = default
      @description = description
      @example = example
      @has_default = !default.nil?
      @validators = []
      @validators << Validators::Required.new if required
    end

    # Required, defaulted, and validation state all live as declarative metadata.
    def required?
      @validators.any?(Validators::Required)
    end

    def has_default?
      @has_default
    end

    def add_validator(validator)
      @validators << validator
      self
    end

    # Evaluate a field block, registering validators via the Configurator DSL.
    def configure(&block)
      Configurator.new(self).instance_exec(&block) if block
      self
    end

    # Read this field's raw value from an input hash, tolerating string or
    # symbol keys. Returns [present?, raw_value].
    def read(input)
      return [false, nil] unless input.respond_to?(:key?)
      return [true, input[name]] if input.key?(name)
      return [true, input[name.to_s]] if input.key?(name.to_s)

      [false, nil]
    end

    # Resolve this field against raw input: presence/default/required, then
    # coerce a present value (#coerce_present), then run validators on the
    # coerced value. Coercion failures raise in strict mode; validation always
    # collects (never fails fast) so every error surfaces in one pass.
    def resolve(input, strict:, path:)
      present, raw = read(input)
      absent = resolve_absent(present, raw, strict:, path:)
      return absent if absent

      result = coerce_present(raw, strict:, path:)
      return result unless result.errors.empty?

      Result.new(result.value, validate_value(result.value, path))
    end

    # The canonical external representation of a coerced value — the inverse of
    # parse. Overridden per field kind; the base is identity (e.g. booleans).
    def dump(value)
      value
    end

    def openapi
      raise NotImplementedError, "#{self.class} must implement #openapi"
    end

    # The RBS type this field's reader returns, e.g. "String", "Array[Employee]".
    def rbs
      raise NotImplementedError, "#{self.class} must implement #rbs"
    end

    # The Sorbet type this field's reader returns, e.g. "String", "T::Array[Employee]".
    def sorbet
      raise NotImplementedError, "#{self.class} must implement #sorbet"
    end

    # Reader return types with nullability applied: required/defaulted fields are
    # non-nilable, optional fields are nilable (the valid-shape contract). Shared
    # by the RBS/RBI string projections and the Tapioca compiler.
    def rbs_return
      non_nilable? ? rbs : "#{rbs}?"
    end

    def sorbet_return
      non_nilable? ? sorbet : "T.nilable(#{sorbet})"
    end

    # A field's reader is non-nilable in the valid-shape contract when it's
    # required or has a default.
    def non_nilable?
      required? || has_default?
    end

    # The nested schema class this field references (object/array fields), or
    # nil. Drives OpenAPI component collection.
    def nested_schema
      nil
    end

    # The GraphQL type reference for this field inside an input block, e.g.
    # "String!", "AddressInput", "[EmployeeInput!]!". Required fields are non-null.
    def graphql_type
      required? ? "#{graphql_ref}!" : graphql_ref
    end

    # Collect the named GraphQL input types this field depends on into `into`
    # (name => SDL). Mirrors the nested_schema-driven OpenAPI collection; scalar
    # fields contribute nothing.
    def graphql_schemas(into)
      nested_schema&.graphql_schemas(into)
    end

    # An OpenAPI $ref to a named schema's component, or the inline schema for an
    # anonymous one.
    def openapi_ref(schema)
      schema.name ? schema.openapi_ref : schema.openapi
    end

    # The bare GraphQL type reference, without nullability. Subclasses supply it;
    # #graphql_type adds the non-null "!" for required fields.
    def graphql_ref
      raise NotImplementedError, "#{self.class} must implement #graphql_ref"
    end

    private

    # Handle the absent/default/required case. Returns a Result when the field
    # is absent (its default, a :required error, or nil), or nil when a value is
    # present and should be coerced. Shared by Field#resolve and the composite
    # MoneyField#resolve.
    def resolve_absent(present, raw, strict:, path:)
      return if present && !raw.nil?
      return Result.ok(resolve_default) if has_default?
      raise MissingField, name if required? && strict
      return Result.failed(error(path, :required)) if required?

      Result.ok(nil)
    end

    # @abstract Coerce a present (non-nil) raw value into a Result.
    def coerce_present(_raw, strict:, path:)
      raise NotImplementedError, "#{self.class} must implement #coerce_present"
    end

    def resolve_default
      default.respond_to?(:call) ? default.call : default
    end

    # Run this field's validators over a coerced value, collecting structured
    # errors. Never raises — aggregation is the whole point, and a validator that
    # blows up (a misapplied rule like `:positive` on a String, a buggy custom
    # block) becomes a collected :validator_error rather than a 500.
    def validate_value(value, path)
      return [] if value.nil?

      validators.flat_map do |validator|
        collector = Validators::Collector.new
        begin
          validator.validate(value, collector)
        rescue StandardError => e
          next [validator_error(path, validator, value, e)]
        end
        collector.violations.map do |violation|
          validation_error(path, validator, value, violation)
        end
      end
    end

    # A validator that raised — collected, never propagated (validations collect
    # even in strict mode).
    def validator_error(path, validator, value, exception)
      full_path = path + [name]
      metadata = { validator: validator.name, exception: exception.class.name }
      Accord.notify(:validator_error, path: full_path, field: name, value:, **metadata)
      Error.new(path: full_path, field: name, code: :validator_error, value:, **metadata)
    end

    def validation_error(path, validator, value, violation)
      code = violation[:code]
      full_path = path + [name]
      Accord.notify(code, path: full_path, field: name, validator: validator.name, value:)
      Error.new(path: full_path, field: name, code:, validator: validator.name, value:, **violation[:metadata])
    end

    # Build an Accord::Error located at this field (path + this field's name).
    def error(path, code, input: nil)
      build_error(path: path + [name], code:, input:)
    end

    # Create a structured error and emit its permissive-parse event. Only ever
    # reached in non-strict mode (strict paths raise before collecting).
    def build_error(path:, code:, input: nil)
      Accord.notify(code, field: name, path:, input:)
      Error.new(field: name, path:, code:, input:)
    end

    # Parse a raw value through a sub-schema at the given (already-built) path.
    # Returns [value, errors]. Shared by ObjectField and ArrayField.
    def parse_object(schema, raw, strict:, path:)
      unless raw.respond_to?(:key?)
        raise CoercionError.new(code: :invalid_object, input: raw) if strict

        return [nil, [build_error(path:, code: :invalid_object, input: raw)]]
      end

      sub = schema.parse(raw, strict:, path:)
      [sub, sub.errors]
    end

    # The field-block DSL. Any registered validator name is a method here
    # (resolved through Accord::Validators), so built-ins and user-registered
    # validators work identically; `validate`/`validator` add custom rules.
    #
    #   currency :salary do
    #     positive
    #     validate { |v| error(:bad) unless (v % 100).zero? }   # name optional
    #   end
    #
    # It subclasses BasicObject deliberately: with almost no inherited methods,
    # no validator name can collide with a Ruby built-in (`format`, `hash`,
    # `test`, ...), and an unknown name raises instead of silently resolving to
    # an inherited method. Everything routes through #method_missing to the
    # registry.
    class Configurator < BasicObject
      def initialize(field)
        @field = field
      end

      # Custom inline rule. The name (default :custom) tags the resulting error's
      # validator; error codes come from the block's `error(:code)` calls.
      def validate(name = :custom, &block)
        @field.add_validator(::Accord::Validators::Custom.new(name, block))
      end

      # Reusable validator: a Validators::Base subclass or instance.
      def validator(validator)
        @field.add_validator(validator.is_a?(::Class) ? validator.new : validator)
      end

      def method_missing(name, *args)
        unless ::Accord::Validators.registered?(name)
          ::Kernel.raise ::NoMethodError,
                         "unknown validator `#{name}` — register it with Accord::Validators.register(:#{name})"
        end

        @field.add_validator(::Accord::Validators.build(name, *args))
      end

      def respond_to_missing?(name, _include_private = false)
        ::Accord::Validators.registered?(name)
      end
    end
  end
end
