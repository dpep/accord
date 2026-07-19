# frozen_string_literal: true

require "uri"
require_relative "string"

module Accord
  module Types
    # A String specialized for HTTP(S) URLs. Validates that the value parses as
    # an absolute http/https URL, and canonicalizes the scheme and host to
    # lowercase (the case-insensitive parts).
    #
    #   url :website
    class URL < String
      SCHEMES = %w[http https].freeze

      def openapi
        { type: "string", format: "uri" }
      end

      private

      def canonicalize(string, strict:) # rubocop:disable Lint/UnusedMethodArgument
        uri = parse_uri(string.strip)
        invalid!(string) unless uri.host && SCHEMES.include?(uri.scheme&.downcase)

        uri.scheme = uri.scheme.downcase
        uri.host = uri.host.downcase
        uri.to_s
      end

      def parse_uri(string)
        ::URI.parse(string)
      rescue ::URI::InvalidURIError
        invalid!(string)
      end
    end
  end
end
