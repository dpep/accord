# frozen_string_literal: true

require_relative "string"

module Accord
  module Types
    # A String specialized for RFC 4122 UUIDs. The canonical internal value is
    # the lowercase, hyphenated form, so equivalent inputs (any case) serialize
    # identically. No wrapper object and no external dependency — validation is
    # a single pattern match.
    #
    #   uuid :id
    #   uuid :event_id, version: 7
    #
    # `version:` is part of the public API; version-specific validation is
    # deferred to a later milestone.
    class UUID < String
      PATTERN = /\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/
      EXAMPLE = "550e8400-e29b-41d4-a716-446655440000"

      attr_reader :version

      def initialize(version: nil)
        @version = version
      end

      # Canonical external form: lowercase, hyphenated.
      def dump(value)
        value&.downcase
      end

      def openapi
        { type: "string", format: "uuid", example: EXAMPLE }
      end

      private

      def canonicalize(string, strict:) # rubocop:disable Lint/UnusedMethodArgument
        normalized = string.strip.downcase
        invalid!(string) unless normalized.match?(PATTERN)

        normalized
      end
    end
  end
end
