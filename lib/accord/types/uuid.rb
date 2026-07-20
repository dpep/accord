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
    #   uuid :event_id, version: 7   # rejects UUIDs that aren't version 7
    class UUID < String
      PATTERN = /\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/

      attr_reader :version

      def initialize(version: nil)
        @version = version
      end

      # Canonical external form: lowercase, hyphenated.
      def dump(value)
        value&.downcase
      end

      def openapi
        { type: "string", format: "uuid", example: "550e8400-e29b-41d4-a716-446655440000" }
      end

      private

      def canonicalize(string, strict:)
        normalized = string.strip.downcase
        invalid!(string) unless normalized.match?(PATTERN)
        invalid!(string) if version && version_of(normalized) != version

        normalized
      end

      # The UUID version: the first hex digit of the third group.
      def version_of(uuid)
        uuid[14].to_i(16)
      end
    end
  end
end
