# frozen_string_literal: true

require_relative "types/registry"
require_relative "types/string"
require_relative "types/uuid"
require_relative "types/email"
require_relative "types/url"
require_relative "types/ip_address"
require_relative "types/phone"
require_relative "types/postal_code"
require_relative "types/zip_code"
require_relative "types/ssn"
require_relative "types/ein"
require_relative "types/routing_number"
require_relative "types/iban"
require_relative "types/iso_currency"
require_relative "types/boolean"
require_relative "types/integer"
require_relative "types/date"
require_relative "types/datetime"
require_relative "types/decimal"
require_relative "types/currency"
require_relative "types/duration"
require_relative "types/percentage"

module Accord
  module Types
    register :string, String
    register :uuid, UUID
    register :email, Email
    register :url, URL
    register :ip_address, IPAddress
    register :phone, Phone
    register :postal_code, PostalCode
    register :zip_code, ZipCode
    register :ssn, SSN
    register :ein, EIN
    register :routing_number, RoutingNumber
    register :iban, IBAN
    register :iso_currency, ISOCurrency
    register :boolean, Boolean
    register :integer, Integer
    register :date, Date
    register :datetime, DateTime
    register :decimal, Decimal
    register :currency, Currency
    register :duration, Duration
    register :percentage, Percentage
  end
end
