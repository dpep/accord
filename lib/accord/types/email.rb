# frozen_string_literal: true

require_relative "string"

module Accord
  module Types
    # A String specialized for email addresses. Canonical form is lowercase, so
    # equivalent addresses compare equal. Validation is a pragmatic format check
    # (not full RFC 5322).
    #
    #   email :contact
    class Email < String
      PATTERN = /\A[^@\s]+@[^@\s]+\.[^@\s]+\z/

      def openapi
        { type: "string", format: "email" }
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
