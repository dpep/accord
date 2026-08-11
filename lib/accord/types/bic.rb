# frozen_string_literal: true

require_relative "string"

module Accord
  module Types
    # A BIC / SWIFT code (ISO 9362) — the bank identifier that accompanies an
    # IBAN, as the ABA routing number does for a US account. Four-letter
    # institution code, two-letter ISO 3166 country, two-character location, and
    # an optional three-character branch. Accepts the spaced/lowercase forms
    # people paste; canonicalizes to uppercase with no spaces.
    #
    #   bic :bank            # or: swift_code :bank
    #
    # A trailing `XXX` branch means "primary office", which is exactly what the
    # 8-character form means — so `DEUTDEFFXXX` canonicalizes to `DEUTDEFF` and
    # the two round-trip identically.
    #
    # Validates the ISO 9362 shape only; the country code isn't checked against
    # the ISO 3166 registry (which changes), same as IBAN.
    class BIC < String
      # institution(4 alpha) + country(2 alpha) + location(2 alnum) + branch(3 alnum, optional)
      PATTERN = /\A[A-Z]{4}[A-Z]{2}[A-Z0-9]{2}([A-Z0-9]{3})?\z/

      def openapi
        { type: "string", format: "bic", example: "DEUTDEFF" }
      end

      private

      def canonicalize(string, strict:)
        compact = string.gsub(/\s/, "").upcase
        invalid!(string) unless PATTERN.match?(compact)

        # Only the branch code (chars 9-11) is droppable — an 8-character code
        # ending in "XXX" is location code, not branch.
        compact.length == 11 ? compact.delete_suffix("XXX") : compact
      end
    end
  end
end
