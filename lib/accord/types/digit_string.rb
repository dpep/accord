# frozen_string_literal: true

module Accord
  module Types
    # Shared by the types whose canonical value is a run of digits people write
    # with punctuation (SSN, EIN, routing number, phone).
    #
    # The motivating case is masked input. Systems routinely *emit* `XXX-XX-6789`
    # or `***-**-6789` for display, and that output comes back as input. Naively
    # keeping the digits would read a mask as a shorter number — or, worse, read
    # `abc123def456ghi789` as a valid SSN. A formatted number contains digits and
    # separators; anything else is a different string, not a number to salvage.
    module DigitString
      private

      # The digits in a formatted number, or nil if it holds anything else.
      def digits_only(string, separators: /[\s-]/)
        digits = string.gsub(separators, "")
        digits if /\A\d+\z/.match?(digits)
      end
    end
  end
end
