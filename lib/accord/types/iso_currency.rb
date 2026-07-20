# frozen_string_literal: true

require_relative "string"

module Accord
  module Types
    # A String specialized for ISO-4217 currency codes. The canonical internal
    # value is the uppercase code (usd -> USD), so equivalent inputs serialize
    # identically. Validated against the (optional) money gem's currency
    # registry, so the full ISO-4217 set is recognized without a hand-maintained
    # list.
    #
    #   iso_currency :currency
    class ISOCurrency < String
      class << self
        def codes
          @codes ||= Money::Currency.all.map(&:iso_code).compact.uniq.sort.freeze
        end
      end

      def initialize
        Accord.require_money!
      end

      # Canonical external form: uppercase.
      def dump(value)
        value&.upcase
      end

      def openapi
        { type: "string", enum: self.class.codes, example: "USD" }
      end

      private

      def canonicalize(string, strict:)
        normalized = string.strip.upcase
        invalid!(string) unless Money::Currency.find(normalized)

        normalized
      end
    end
  end
end
