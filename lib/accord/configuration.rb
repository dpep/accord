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
    attr_accessor :strict, :default_currency, :notifications, :observe_coercions, :input_reader,
                  :default_phone_country_code, :version_resolver

    def initialize
      @strict = false
      @default_currency = nil
      @notifications = true    # emit accord.parse.<code> error/rounding events
      @observe_coercions = false # emit accord.parse.coerced (permissive -> strict signal)
      @input_reader = :input   # default reader name for `accepts` (override per-action with `as:`)
      @default_phone_country_code = "1" # NANP (US/Canada); the `phone` type's default calling code
      # Delegate API-version detection to your versioning library: a
      # `->(controller) { ... }` returning the request's version. Accord matches
      # that label to a versioned `accepts`/`returns`; it does not detect versions.
      @version_resolver = nil
    end
  end
end
