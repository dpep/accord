# frozen_string_literal: true

require_relative "postal_code"

module Accord
  module Types
    # A US ZIP code — the US-only convenience alias for PostalCode. Accepts
    # `12345`, `12345-6789`, and raw `123456789`; canonicalizes to `12345` or the
    # hyphenated `12345-6789`. A space-separated `12345 6789` is rejected.
    #
    #   zip_code :postal_code
    #
    # For Canada (or any parameterized country) use `postal_code, country:`.
    class ZipCode < PostalCode
      def initialize
        super(country: :us)
      end

      def openapi
        { type: "string", format: "zip-code", example: "12345" }
      end
    end
  end
end
