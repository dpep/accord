# frozen_string_literal: true

require_relative "string"

module Accord
  module Types
    # A US Social Security Number. Accepts `123-45-6789`, `123 45 6789`, and raw
    # `123456789`; canonicalizes to the hyphenated `AAA-GG-SSSS`. Rejects the
    # structurally-invalid ranges (area `000`/`666`/`900–999`, group `00`, serial
    # `0000`) as well as bad length — real validation, not just nine digits.
    #
    #   ssn :taxpayer_id
    class SSN < String
      def openapi
        { type: "string", format: "ssn", example: "123-45-6789" }
      end

      private

      def canonicalize(string, strict:)
        digits = string.gsub(/\D/, "")
        invalid!(string) unless digits.length == 9 && valid_ssn?(digits)

        "#{digits[0, 3]}-#{digits[3, 2]}-#{digits[5, 4]}"
      end

      def valid_ssn?(digits)
        area = digits[0, 3].to_i
        group = digits[3, 2].to_i
        serial = digits[5, 4].to_i
        !(area.zero? || area == 666 || area >= 900 || group.zero? || serial.zero?)
      end
    end
  end
end
