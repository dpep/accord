# frozen_string_literal: true

require_relative "decimal"

module Accord
  module Types
    # A Decimal carrying the semantic meaning of a time duration in a declared
    # unit. The field name conveys intent (`duration :hours`); the parsed value
    # is a plain BigDecimal — no value object, no unit conversion, and no
    # alternate syntaxes (1h, 90m, 01:30, PT1H30M) for now. Parsing is
    # intentionally the generic Decimal's; Duration adds only defaults and
    # OpenAPI metadata. A richer Accord::Duration value object can arrive later
    # without changing the DSL.
    #
    #   duration :work_time, unit: :hours
    #   duration :elapsed_time, unit: :seconds, scale: 3
    class Duration < Decimal
      UNITS = %i[hours minutes seconds].freeze

      attr_reader :unit

      def initialize(unit: :hours, scale: 2, round: false)
        unless UNITS.include?(unit)
          raise ArgumentError, "unknown duration unit: #{unit.inspect} (expected one of #{UNITS.join(", ")})"
        end

        @unit = unit
        super(scale:, round:)
      end

      def openapi
        super.merge(description: "Duration in #{unit}", example: "1.50")
      end
    end
  end
end
