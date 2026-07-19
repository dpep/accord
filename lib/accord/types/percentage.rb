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
      def initialize(scale: 2, round: false)
        super
      end

      def openapi
        super.merge(format: "percentage")
      end
    end
  end
end
