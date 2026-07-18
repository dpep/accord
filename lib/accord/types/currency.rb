# frozen_string_literal: true

require "bigdecimal"
require_relative "../type"

module Accord
  module Types
    # Canonical internal value: a BigDecimal. Never a Float — Floats are
    # rejected in strict mode and routed through their string form otherwise,
    # so binary rounding never enters the pipeline.
    #
    # strict:      plain numeric strings ("10", "10.50") and integers.
    # permissive:  additionally strips currency formatting ("$1,000.00").
    class Currency < Type
      STRICT_STRING = /\A-?\d+(\.\d+)?\z/
      FORMATTING = /[$,\s]/

      def dump(value)
        value&.to_s("F")
      end

      def openapi
        { type: "number" }
      end

      private

      def coerce(value, strict:)
        case value
        when BigDecimal then value
        when ::Integer then BigDecimal(value)
        when ::Float then coerce_float(value, strict:)
        when ::String then coerce_string(value, strict:)
        else invalid!(value)
        end
      end

      def coerce_float(value, strict:)
        invalid!(value) if strict

        BigDecimal(value.to_s)
      end

      def coerce_string(str, strict:)
        cleaned = strict ? str.strip : str.gsub(FORMATTING, "")
        invalid!(str) if strict && !cleaned.match?(STRICT_STRING)

        decimal = BigDecimal(cleaned, exception: false)
        invalid!(str) unless decimal

        decimal
      end
    end
  end
end
