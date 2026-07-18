# frozen_string_literal: true

require_relative "../type"

module Accord
  module Types
    # Canonical internal value: a String.
    #
    # strict:      only accepts a String.
    # permissive:  also coerces Symbol and Numeric via #to_s.
    class String < Type
      COERCIBLE = [::String, ::Symbol, ::Numeric].freeze

      def openapi
        { type: "string" }
      end

      private

      def coerce(value, strict:)
        return value if value.is_a?(::String)

        invalid!(value) if strict
        invalid!(value) unless COERCIBLE.any? { |klass| value.is_a?(klass) }

        value.to_s
      end
    end
  end
end
