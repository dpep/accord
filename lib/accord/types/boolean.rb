# frozen_string_literal: true

require_relative "../type"

module Accord
  module Types
    # Canonical internal value: true or false.
    #
    # strict:      only accepts true / false.
    # permissive:  also accepts the common string encodings below.
    class Boolean < Type
      TRUE_STRINGS = %w[true 1 yes].freeze
      FALSE_STRINGS = %w[false 0 no].freeze

      def openapi
        { type: "boolean" }
      end

      def rbs
        "bool"
      end

      def sorbet
        "T::Boolean"
      end

      def graphql
        "Boolean"
      end

      private

      def coerce(value, strict:)
        return value if value == true || value == false

        invalid!(value) if strict

        normalized = value.to_s.strip.downcase
        return true if TRUE_STRINGS.include?(normalized)
        return false if FALSE_STRINGS.include?(normalized)

        invalid!(value)
      end
    end
  end
end
