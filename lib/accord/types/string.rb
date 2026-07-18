# frozen_string_literal: true

require_relative "../type"

module Accord
  module Types
    # Canonical internal value: a String. The reference base for semantic string
    # types (UUID, Email, URL, ...): coerce to a base String, then hand it to
    # #canonicalize, which subclasses override to normalize and validate.
    #
    # strict:      only accepts a String.
    # permissive:  also coerces Symbol and Numeric via #to_s.
    class String < Type
      COERCIBLE = [::String, ::Symbol, ::Numeric].freeze

      def openapi
        { type: "string" }
      end

      def rbs
        "String"
      end

      private

      def coerce(value, strict:)
        canonicalize(string_value(value, strict:), strict:)
      end

      # External value -> a base String. Raises on un-coercible input.
      def string_value(value, strict:)
        return value if value.is_a?(::String)

        invalid!(value) if strict
        invalid!(value) unless COERCIBLE.any? { |klass| value.is_a?(klass) }

        value.to_s
      end

      # Hook for semantic string types to normalize/validate a base String.
      # The base String type is identity.
      def canonicalize(string, strict:) # rubocop:disable Lint/UnusedMethodArgument
        string
      end
    end
  end
end
