# frozen_string_literal: true

require_relative "string"
require_relative "digit_string"

module Accord
  module Types
    # A US Employer Identification Number — nine digits, canonicalized to the
    # hyphenated `XX-XXXXXXX`. Accepts `12-3456789` and raw `123456789`; rejects
    # a masked `**-***6789`.
    #
    #   ein :employer_id
    #
    # Validates length/shape only; the IRS prefix set is maintained and changes,
    # so it isn't baked in here.
    class EIN < String
      include DigitString

      def openapi
        { type: "string", format: "ein", example: "12-3456789" }
      end

      private

      def canonicalize(string, strict:)
        digits = digits_only(string)
        invalid!(string) unless digits&.length == 9

        "#{digits[0, 2]}-#{digits[2, 7]}"
      end
    end
  end
end
