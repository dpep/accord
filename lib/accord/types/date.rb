# frozen_string_literal: true

require "date"
require_relative "../type"

module Accord
  module Types
    # Canonical internal value: a ::Date.
    #
    # strict:      accepts Date/Time/DateTime and ISO-8601 strings.
    # permissive:  additionally accepts strings matching any of the configured
    #              legacy `formats` (strptime patterns).
    #
    #   date :dob, formats: ["%m/%d/%Y"]
    class Date < Type
      attr_reader :formats

      def initialize(formats: [])
        @formats = Array(formats)
      end

      def dump(value)
        value&.iso8601
      end

      def openapi
        { type: "string", format: "date" }
      end

      def rbs
        "Date"
      end

      def sorbet
        "Date"
      end

      private

      def coerce(value, strict:)
        case value
        when ::Date then value
        when ::Time, ::DateTime then value.to_date
        when ::String then coerce_string(value, strict:)
        else invalid!(value)
        end
      end

      def coerce_string(str, strict:)
        iso = ::Date.iso8601(str) rescue nil
        return iso if iso

        unless strict
          formats.each do |format|
            parsed = ::Date.strptime(str, format) rescue nil
            return parsed if parsed
          end
        end

        invalid!(str)
      end
    end
  end
end
