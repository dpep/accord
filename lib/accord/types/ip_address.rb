# frozen_string_literal: true

require "ipaddr"
require_relative "string"

module Accord
  module Types
    # A String specialized for IP addresses (IPv4 or IPv6). Canonicalizes via
    # IPAddr — e.g. an IPv6 address is lowercased and compressed
    # (`2001:DB8:0:0:0:0:0:1` → `2001:db8::1`).
    #
    #   ip_address :client_ip
    class IPAddress < String
      def openapi
        { type: "string", format: "ip" }
      end

      private

      def canonicalize(string, strict:) # rubocop:disable Lint/UnusedMethodArgument
        ::IPAddr.new(string.strip).to_s
      rescue ::IPAddr::Error
        invalid!(string)
      end
    end
  end
end
