# frozen_string_literal: true

require_relative "decimal"

module Accord
  module Types
    # A Decimal carrying the semantic meaning of a percentage (e.g. 0..100).
    # Default scale 2. Bounds are expressed with validators (`min`/`max`/
    # `between`) rather than baked into the type.
    #
    #   percentage :discount do
    #     between 0..100
    #   end
    class Percentage < Decimal
      # A trailing `%`, optionally preceded by whitespace — anchored, so a `%`
      # anywhere else is not stripped (and therefore rejected).
      TRAILING_SYMBOL = /\s*%\z/

      def initialize(scale: 2, round: false)
        super
      end

      def openapi
        super.merge(format: "percentage")
      end

      private

      # Strict percentage accepts plain numeric strings only; permissive trims
      # surrounding whitespace and strips a trailing `%` (`"50%"` -> 50),
      # mirroring how Currency strips a leading `$` — so `"5%0"` and `"%50"` are
      # rejected.
      def parse_string(str, strict:)
        return super if strict

        cleaned = str.strip.sub(TRAILING_SYMBOL, "")
        invalid!(str) unless cleaned.match?(NUMERIC)

        cleaned
      end
    end
  end
end
