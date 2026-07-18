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
      FORMATTING = /[$,\s]/

      def initialize(scale: 2, round: false)
        super
      end

      def openapi
        super.merge(example: "1234.56")
      end

      private

      # Strict currency accepts plain numeric strings only; permissive strips
      # currency formatting first.
      def parse_string(str, strict:)
        return super if strict

        cleaned = str.gsub(FORMATTING, "")
        invalid!(str) unless cleaned.match?(NUMERIC)

        cleaned
      end
    end
  end
end
