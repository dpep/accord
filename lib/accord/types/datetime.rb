# frozen_string_literal: true

require "time"
require_relative "../type"

module Accord
  module Types
    # Canonical internal value: a ::Time (timestamp, preserving time-of-day and
    # offset — unlike Date, which narrows to a day).
    #
    # strict:      accepts Time/DateTime and ISO-8601 strings.
    # permissive:  additionally accepts strings matching any configured legacy
    #              `formats` (strptime patterns).
    #
    #   datetime :starts_at
    #   datetime :legacy_at, formats: ["%m/%d/%Y %H:%M"]
    class DateTime < Type
      attr_reader :formats

      def initialize(formats: [])
        @formats = Array(formats)
      end

      def dump(value)
        value&.iso8601
      end

      def openapi
        { type: "string", format: "date-time" }
      end

      def rbs
        "Time"
      end

      def sorbet
        "Time"
      end

      # graphql-ruby's ISO8601DateTime scalar (or String if you don't use it).
      def graphql
        "ISO8601DateTime"
      end

      private

      def coerce(value, strict:)
        case value
        when ::Time then value
        when ::DateTime then value.to_time
        when ::String then coerce_string(value, strict:)
        else invalid!(value)
        end
      end

      def coerce_string(str, strict:)
        iso = ::Time.iso8601(str) rescue nil
        return iso if iso

        unless strict
          formats.each do |format|
            parsed = ::Time.strptime(str, format) rescue nil
            return parsed if parsed
          end
        end

        invalid!(str)
      end
    end
  end
end
