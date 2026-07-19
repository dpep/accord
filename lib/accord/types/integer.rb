# frozen_string_literal: true

require_relative "../type"

module Accord
  module Types
    # Canonical internal value: an Integer.
    #
    # strict:      only accepts an Integer.
    # permissive:  also coerces integer-valued strings ("42") and whole Floats.
    class Integer < Type
      INTEGER_STRING = /\A-?\d+\z/

      def openapi
        { type: "integer" }
      end

      def rbs
        "Integer"
      end

      def sorbet
        "Integer"
      end

      private

      def coerce(value, strict:)
        case value
        when ::Integer then value
        when ::String then coerce_string(value, strict:)
        when ::Float then coerce_float(value, strict:)
        else invalid!(value)
        end
      end

      def coerce_string(str, strict:)
        invalid!(str) if strict

        cleaned = str.strip
        invalid!(str) unless cleaned.match?(INTEGER_STRING)

        cleaned.to_i
      end

      def coerce_float(value, strict:)
        invalid!(value) if strict
        invalid!(value) unless value == value.to_i

        value.to_i
      end
    end
  end
end
