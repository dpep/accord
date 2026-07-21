# frozen_string_literal: true

require_relative "string"

module Accord
  module Types
    # A North-American (NANP) phone number, canonicalized to E.164
    # (`+15551234567`). Accepts the common written forms — `(555) 123-4567`,
    # `555-123-4567`, `555.123.4567`, `+1 555 123 4567`, `1-555-123-4567`, and
    # raw `5551234567` — by stripping formatting to digits, then validating a
    # 10-digit national number (optionally prefixed by the country code).
    #
    #   phone :mobile
    #   phone :mobile, country_code: "44"   # override the default calling code
    #
    # The default calling code is per-field `country_code:`, else
    # `Accord.config.default_phone_country_code` (`"1"`, US/Canada). This is
    # deliberately not libphonenumber — it validates NANP length + shape, not
    # every national numbering plan.
    class Phone < String
      def initialize(country_code: nil)
        @country_code = (country_code || Accord.config.default_phone_country_code).to_s.sub(/\A\+/, "")
      end

      attr_reader :country_code

      def openapi
        { type: "string", format: "phone", example: "+15551234567" }
      end

      private

      def canonicalize(string, strict:)
        digits = string.gsub(/\D/, "")
        national =
          if digits.length == 10
            digits
          elsif digits.length == @country_code.length + 10 && digits.start_with?(@country_code)
            digits[@country_code.length..]
          else
            invalid!(string)
          end

        "+#{@country_code}#{national}"
      end
    end
  end
end
