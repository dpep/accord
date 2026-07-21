# frozen_string_literal: true

require_relative "string"

module Accord
  module Types
    # A postal code, parameterized by country — the general form that folds the
    # per-country formats together (rather than a type per country). Defaults to
    # the US; add more countries by teaching it a `canon_<country>` method.
    #
    #   postal_code :zip                 # US (default)
    #   postal_code :postcode, country: :ca
    #
    # US canonicalizes to `12345` / `12345-6789`; Canada to the uppercase,
    # single-spaced `A1A 1A1`. `zip_code` is the US-only convenience alias.
    class PostalCode < String
      SUPPORTED = %i[us ca].freeze

      def initialize(country: :us)
        @country = country.to_sym
        return if SUPPORTED.include?(@country)

        raise ArgumentError, "unsupported postal country #{@country.inspect} (supported: #{SUPPORTED.join(", ")})"
      end

      attr_reader :country

      def openapi
        { type: "string", format: "postal-code", example: @country == :ca ? "A1A 1A1" : "12345" }
      end

      private

      def canonicalize(string, strict:)
        send(:"canon_#{@country}", string) || invalid!(string)
      end

      # US ZIP / ZIP+4: `12345` or `12345-6789` (raw 9 digits allowed).
      def canon_us(string)
        match = /\A(\d{5})(\d{4})?\z/.match(string.delete("-")) or return

        match[2] ? "#{match[1]}-#{match[2]}" : match[1]
      end

      # Canadian `A1A 1A1` — valid first-position letters, canonical single space.
      def canon_ca(string)
        match = /\A([ABCEGHJ-NPRSTVXY]\d[A-Z])(\d[A-Z]\d)\z/.match(string.gsub(/\s/, "").upcase) or return

        "#{match[1]} #{match[2]}"
      end
    end
  end
end
