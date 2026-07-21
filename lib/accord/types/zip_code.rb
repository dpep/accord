# frozen_string_literal: true

require_relative "string"

module Accord
  module Types
    # A US ZIP code — five digits, or ZIP+4. Accepts `12345`, `12345-6789`, and
    # raw `123456789`; canonicalizes to `12345` or the hyphenated `12345-6789`.
    # A space-separated `12345 6789` is not a standard form and is rejected.
    #
    #   zip_code :postal_code
    #
    # US-only. Other North-American postal codes are different formats — Canadian
    # codes are `A1A 1A1`, not digits — so they'd be their own type, not an
    # option here.
    class ZipCode < String
      PATTERN = /\A(\d{5})(\d{4})?\z/

      def openapi
        { type: "string", format: "zip-code", example: "12345" }
      end

      private

      def canonicalize(string, strict:)
        match = PATTERN.match(string.delete("-")) || invalid!(string)
        match[2] ? "#{match[1]}-#{match[2]}" : match[1]
      end
    end
  end
end
