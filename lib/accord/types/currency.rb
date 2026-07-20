# frozen_string_literal: true

require_relative "decimal"

module Accord
  module Types
    # A Decimal specialized for money: default scale 2, strips currency
    # formatting (currency symbol, thousands separators) when permissive, and
    # documents itself as a decimal string in OpenAPI — strings avoid the
    # cross-language float ambiguity a JSON number would introduce.
    #
    #   currency :salary            # scale: 2
    #   currency :bonus, scale: 4
    class Currency < Decimal
      # A leading `$`, optionally followed by whitespace — anchored, so a `$`
      # anywhere else is not stripped (and therefore rejected).
      LEADING_SYMBOL = /\A\$\s*/

      def initialize(scale: 2, round: false)
        super
      end

      def openapi
        super.merge(example: "1234.56")
      end

      private

      # Strict currency accepts plain numeric strings only; permissive trims
      # surrounding whitespace, strips a leading `$` and thousands-separator
      # commas, then requires a plain number — so `"1$234"`, `"12 34"`, `"$$5"`
      # are rejected.
      def parse_string(str, strict:)
        return super if strict

        cleaned = str.strip.sub(LEADING_SYMBOL, "").delete(",")
        invalid!(str) unless cleaned.match?(NUMERIC)

        cleaned
      end
    end
  end
end
