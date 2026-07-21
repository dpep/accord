# frozen_string_literal: true

require_relative "string"

module Accord
  module Types
    # A US bank routing number (ABA transit number): nine digits validated by the
    # ABA check-digit algorithm, not just length. Strips any formatting to the
    # canonical nine digits.
    #
    #   routing_number :aba
    #
    # US-only. The international equivalent — IBAN + BIC/SWIFT — is a different
    # scheme entirely (a separate future type), not a variant of this.
    class RoutingNumber < String
      def openapi
        { type: "string", format: "aba-routing-number", example: "021000021" }
      end

      private

      def canonicalize(string, strict:)
        digits = string.gsub(/\D/, "")
        invalid!(string) unless digits.length == 9 && aba_checksum_valid?(digits)

        digits
      end

      # 3(d1+d4+d7) + 7(d2+d5+d8) + (d3+d6+d9) ≡ 0 (mod 10)
      def aba_checksum_valid?(digits)
        n = digits.chars.map { |c| c.to_i }
        (3 * (n[0] + n[3] + n[6]) + 7 * (n[1] + n[4] + n[7]) + (n[2] + n[5] + n[8])) % 10 == 0
      end
    end
  end
end
