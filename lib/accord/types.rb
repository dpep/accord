# frozen_string_literal: true

require_relative "types/registry"
require_relative "types/string"
require_relative "types/uuid"
require_relative "types/email"
require_relative "types/url"
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
