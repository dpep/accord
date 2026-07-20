# frozen_string_literal: true

require_relative "errors"

module Accord
  # Base class for scalar types. A type is the single source of truth for
  # coercing an external value into a canonical internal Ruby object, and back.
  #
  # The common interface:
  #   type.parse(value)   # permissive, returns nil on failure (logs)
  #   type.parse!(value)  # strict, raises CoercionError on failure
  #   type.dump(value)    # internal -> external representation
  #   type.openapi        # OpenAPI schema fragment
  #
  # Subclasses implement #coerce(value, strict:) which returns the canonical
  # value or raises CoercionError. `strict:` flows into coercion because some
  # types (e.g. Boolean) accept a wider set of inputs when permissive.
  class Type
    class << self
      def instance
        @instance ||= new
      end

      def parse(value) = instance.parse(value)
      def parse!(value) = instance.parse!(value)
      def dump(value) = instance.dump(value)
      def openapi = instance.openapi
    end

    # Canonical coercion entry used by schemas. Raises CoercionError. Surrounding
    # whitespace on string input is trimmed here, once, for every type (`" 42 "`,
    # `" true "`, `"  Ada  "`) — incidental whitespace is never canonical. Opt out
    # per field where it's significant: `string :bio, strip: false`.
    def cast(value, strict:)
      return if value.nil?

      value = value.strip if value.is_a?(::String) && strip_whitespace?
      coerce(value, strict:)
    end

    # Whether cast trims surrounding whitespace from string input. True for every
    # type; the base String type honors a per-field `strip:` option.
    def strip_whitespace?
      true
    end

    # Strict: raises on invalid input.
    def parse!(value)
      cast(value, strict: true)
    end

    # Permissive standalone: logs and returns nil on invalid input.
    def parse(value)
      cast(value, strict: false)
    rescue CoercionError => e
      Accord.logger&.warn("accord: dropped invalid #{type_name} #{e.input.inspect}")
      nil
    end

    def dump(value)
      value
    end

    def openapi
      raise NotImplementedError, "#{self.class} must implement #openapi"
    end

    # The RBS type of the canonical internal value, e.g. "String", "BigDecimal".
    def rbs
      raise NotImplementedError, "#{self.class} must implement #rbs"
    end

    # The Sorbet type of the canonical internal value, e.g. "String", "T::Boolean".
    def sorbet
      raise NotImplementedError, "#{self.class} must implement #sorbet"
    end

    # The GraphQL scalar type this maps to, e.g. "String", "Int", "Boolean".
    # Semantic scalars whose canonical external form is a string (UUID, Decimal,
    # ...) map to "String"; that's the dump representation a client sends.
    def graphql
      raise NotImplementedError, "#{self.class} must implement #graphql"
    end

    # The Ruby class of the canonical value, used to reject inapplicable
    # validators at declaration time (e.g. `positive` on a boolean). nil when the
    # value has no single class to check against (Boolean's true/false).
    def value_class
      nil
    end

    # Short symbol name for a type, e.g. Accord::Types::Currency -> :currency.
    def type_name
      self.class.name.split("::").last.gsub(/([a-z])([A-Z])/, '\1_\2').downcase.to_sym
    end

    private

    def coerce(_value, strict:)
      raise NotImplementedError, "#{self.class} must implement #coerce"
    end

    # Convenience for subclasses to signal an un-coercible value.
    def invalid!(input, code: :"invalid_#{type_name}")
      raise CoercionError.new(code:, input:)
    end
  end
end
