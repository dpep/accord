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
                  :default_phone_country_code, :version_header, :version_resolver

    def initialize
      @strict = false
      @default_currency = nil
      @notifications = true    # emit accord.parse.<code> error/rounding events
      @observe_coercions = false # emit accord.parse.coerced (permissive -> strict signal)
      @input_reader = :input   # default reader name for `accepts` (override per-action with `as:`)
      @default_phone_country_code = "1" # NANP (US/Canada); the `phone` type's default calling code
      @version_header = "X-API-Version" # request header the `version` DSL reads by default
      @version_resolver = nil  # override: a `->(controller) { ... }` (e.g. a version-lookup library)
    end
  end
end
