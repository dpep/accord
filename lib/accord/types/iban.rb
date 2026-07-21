# frozen_string_literal: true

require_relative "string"

module Accord
  module Types
    # An International Bank Account Number (ISO 13616) — the international scheme
    # (with BIC/SWIFT) that the US ABA routing number is *not*. Validated by the
    # ISO 7064 mod-97 checksum, not just shape. Accepts the grouped, spaced form
    # banks print (`GB82 WEST 1234 5698 7654 32`); canonicalizes to uppercase,
    # no spaces.
    #
    #   iban :account
    class IBAN < String
      # 2-letter country + 2 check digits + up to 30 alphanumeric; 15–34 total.
      PATTERN = /\A[A-Z]{2}\d{2}[A-Z0-9]{11,30}\z/

      def openapi
        { type: "string", format: "iban", example: "GB82WEST12345698765432" }
      end

      private

      def canonicalize(string, strict:)
        compact = string.gsub(/\s/, "").upcase
        invalid!(string) unless PATTERN.match?(compact) && mod97(compact) == 1

        compact
      end

      # Move the first four chars to the end, map letters to numbers (A=10..Z=35),
      # then take the whole thing mod 97.
      def mod97(iban)
        digits = (iban[4..] + iban[0, 4]).chars.map { |char| char.match?(/[A-Z]/) ? (char.ord - 55) : char }.join
        digits.to_i % 97
      end
    end
  end
end
