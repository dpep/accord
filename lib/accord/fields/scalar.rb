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

    # Reject a validator that can't run against this field's type at declaration
    # time — a misapplied rule (`positive` on a boolean) is a schema bug, so fail
    # fast at boot rather than 500 on a request.
    def add_validator(validator)
      unless validator.applicable_to?(type)
        raise ArgumentError, "`#{validator.name}` cannot validate #{type.type_name} field #{name.inspect}"
      end

      super
    end

    def openapi
      schema = type.openapi.dup
      validators.each { |validator| schema.merge!(validator.openapi) }
      schema[:description] = description if description
      schema[:example] = example unless example.nil?
      schema
    end

    # Coerce a static default to its canonical value and check it against the
    # field's own validators — both at boot, so a bad default (`default: "yes"`
    # for a boolean, or a default that violates `min`) is caught at declaration.
    def check_default!
      return self unless has_default? && !default.respond_to?(:call)

      @default = coerce_default(default)
      errors = validate_value(@default, [])
      return self if errors.empty?

      raise ArgumentError, "default #{default.inspect} for #{name.inspect} violates #{errors.map(&:code).join(", ")}"
    end

    def dump(value)
      type.dump(value)
    end

    def rbs
      type.rbs
    end

    def sorbet
      type.sorbet
    end

    def graphql_ref
      type.graphql
    end

    private

    # Proc defaults are coerced when they run (their value isn't known at boot);
    # static defaults were already coerced in #check_default!.
    def resolve_default
      value = super
      default.respond_to?(:call) ? coerce_default(value) : value
    end

    # Defaults coerce permissively, like input (so `default: "yes"` is a valid
    # boolean), but an uncoercible default is a declaration error.
    def coerce_default(value)
      type.cast(value, strict: false)
    rescue CoercionError
      raise ArgumentError, "default #{value.inspect} for #{name.inspect} is not a valid #{type.type_name}"
    end

    def coerce_present(raw, strict:, path:)
      value = type.cast(raw, strict:)
      observe_permissive_coercion(raw, value, path) if !strict && Accord.observe_coercions?
      Result.ok(value)
    rescue CoercionError => e
      raise if strict

      Result.failed(error(path, e.code, input: e.input))
    end

    # If the value only coerced because permissive rules accepted input that
    # strict rules would reject, emit accord.parse.coerced — carrying the raw
    # input (the "variant" seen) and the canonical value. When a field stops
    # emitting these, it's safe to make it strict.
    def observe_permissive_coercion(raw, value, path)
      type.cast(raw, strict: true)
    rescue CoercionError
      Accord.notify_coerced(field: name, path: path + [name], input: raw, value:, type: type.type_name)
    end
  end
end
