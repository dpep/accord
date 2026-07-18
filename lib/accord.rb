# frozen_string_literal: true

require_relative "accord/version"
require_relative "accord/errors"
require_relative "accord/type"
require_relative "accord/types/string"
require_relative "accord/types/boolean"
require_relative "accord/types/date"
require_relative "accord/types/currency"
require_relative "accord/field"
require_relative "accord/validation"
require_relative "accord/schema"

# Accord — executable API contracts for Ruby.
#
# A schema declares the accepted input for an API boundary: it coerces
# untrusted values into typed Ruby objects, validates them, collects
# structured errors, and documents the contract.
module Accord
  class << self
    # Optional logger used by permissive standalone type coercion to record
    # dropped values. Rails integration (Milestone 3) will layer
    # ActiveSupport::Notifications on top of this hook.
    attr_accessor :logger
  end
end
