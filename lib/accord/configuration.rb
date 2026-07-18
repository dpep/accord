# frozen_string_literal: true

module Accord
  # Library-level configuration.
  #
  #   Accord.configure do |c|
  #     c.strict = false   # default parse mode
  #   end
  #
  # Per-call `strict:` always overrides the configured default. The shipped
  # default is non-strict — an API boundary tolerates and reports; strict is
  # the trusted-internal-caller mode.
  class Configuration
    attr_accessor :strict

    def initialize
      @strict = false
    end
  end
end
