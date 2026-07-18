# frozen_string_literal: true

require "bigdecimal"
require_relative "../type"

module Accord
  module Types
    # Canonical internal value: a BigDecimal. Never a Float — Floats are rejected
    # in strict mode and otherwise routed through their string form, so binary
    # rounding never enters the pipeline.
    #
    # Internal representation is kept separate from external formatting: `parse`
    # coerces and enforces scale, `dump` renders a canonical string with exactly
    # `scale` decimal places.
    #
    #   decimal :exchange_rate, scale: 8
    #
    # Scale is enforced, not silently applied. Input with more precision than
    # `scale` is rejected (strict raises; non-strict collects an :invalid_scale
    # error and emits its event) — unless `round: true` is configured, which
    # rounds to `scale` instead. Rounding never happens silently.
    #
    # This type is the reference architecture for scalar types: a coercion
    # pipeline (external → canonical), scale/validation, and a dump projection.
    class Decimal < Type
      DEFAULT_SCALE = 4
      NUMERIC = /\A-?\d+(\.\d+)?\z/

      attr_reader :scale

      def initialize(scale: DEFAULT_SCALE, round: false)
        @scale = scale
        @round = round
      end

      def round?
        @round
      end

      # Canonical external form: a string with exactly `scale` decimal places.
      def dump(value)
        return if value.nil?

        integer, _, fraction = value.round(scale).to_s("F").partition(".")
        return integer if scale.zero?

        "#{integer}.#{fraction.ljust(scale, "0")[0, scale]}"
      end

      def openapi
        { type: "string", format: "decimal" }
      end

      private

      def coerce(value, strict:)
        decimal = BigDecimal(decimal_string(value, strict:), exception: false)
        invalid!(value) unless decimal

        enforce_scale(decimal, value, strict:)
      end

      # External value -> a plain decimal string. Raises on un-parseable input.
      def decimal_string(value, strict:)
        case value
        when BigDecimal then value.to_s("F")
        when ::Integer then value.to_s
        when ::Float then float_string(value, strict:)
        when ::String then parse_string(value, strict:)
        else invalid!(value)
        end
      end

      def float_string(value, strict:)
        invalid!(value) if strict

        value.to_s
      end

      # Plain decimal strings only. Currency overrides to strip formatting.
      def parse_string(str, strict:) # rubocop:disable Lint/UnusedMethodArgument
        cleaned = str.strip
        invalid!(str) unless cleaned.match?(NUMERIC)

        cleaned
      end

      def enforce_scale(decimal, input, strict:)
        return decimal if decimal == decimal.round(scale)
        raise CoercionError.new(code: :invalid_scale, input:) unless round?

        rounded = decimal.round(scale)
        Accord.instrument(:rounded, input:, scale:, value: rounded) unless strict
        rounded
      end
    end
  end
end
