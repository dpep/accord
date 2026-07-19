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

    # Canonical coercion entry used by schemas. Raises CoercionError.
    def cast(value, strict:)
      return if value.nil?

      coerce(value, strict:)
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
