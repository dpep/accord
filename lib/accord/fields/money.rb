# frozen_string_literal: true

require_relative "../field"
require_relative "scalar"
require_relative "../types/decimal"
require_relative "../types/iso_currency"

module Accord
  # A composite field representing an amount + currency, parsed into a `money`
  # gem Money value. Money is a reusable composition of existing scalar types,
  # not a new primitive: the amount reuses Decimal, the currency reuses
  # ISOCurrency, and errors nest exactly like any other sub-structure — no
  # special cases.
  #
  #   money :salary                                  # nested { amount:, currency: }
  #   money :salary, format: :flat                   # salary: "..", salary_currency: ".."
  #   money :salary, currency: "USD"                 # fixed currency, amount only
  #   money :salary, format: :flat, currency_field: :ccy   # aliased currency key
  #
  # Dump always emits the canonical nested { amount:, currency: } form,
  # regardless of the input format.
  class MoneyField < Field
    FORMATS = %i[nested flat].freeze

    def initialize(format: :nested, currency: nil, round: false, amount_field: nil, currency_field: nil, **opts)
      super(**opts)
      Accord.require_money!
      raise ArgumentError, "unknown money format: #{format.inspect}" unless FORMATS.include?(format)

      @format = format
      @round = round
      @amount_type = Types::Decimal.new # representative instance for OpenAPI (scale-independent)
      @currency_type = Types::ISOCurrency.new
      @fixed_currency = currency ? @currency_type.parse!(currency) : nil
      @amount_name = amount_key(amount_field)
      @currency = ScalarField.new(name: currency_key(currency_field), type: @currency_type, required: true)
    end

    # Resolve against the full input — flat format sources the amount and
    # currency from sibling keys, so the base #read (which reads a single key)
    # doesn't fit. Presence/default/required policy mirrors the base template.
    def resolve(input, strict:, path:)
      present, raw = read(input)

      if !present || raw.nil?
        return Result.ok(resolve_default) if has_default?
        raise MissingField, name if required? && strict
        return Result.failed(error(path, :required)) if required?

        return Result.ok(nil)
      end

      coerce_money(input, raw, strict:, path:)
    end

    def dump(value)
      return if value.nil?

      {
        amount: Types::Decimal.new(scale: value.currency.exponent).dump(value.amount),
        currency: @currency_type.dump(value.currency.iso_code),
      }
    end

    def openapi
      currency = @fixed_currency ? { type: "string", enum: [@fixed_currency] } : @currency_type.openapi

      {
        type: "object",
        properties: { amount: @amount_type.openapi, currency: },
        required: %i[amount currency],
      }
    end

    def rbs
      "Money"
    end

    private

    def coerce_money(input, raw, strict:, path:)
      component_input, component_path =
        if @format == :nested
          return nested_shape_error(raw, strict:, path:) unless raw.respond_to?(:key?)

          [raw, path + [name]]
        else
          [input, path]
        end

      # Resolve the currency first so the amount's scale is currency-aware.
      currency = resolve_currency(component_input, strict:, path: component_path)
      amount = amount_field(currency).resolve(component_input, strict:, path: component_path)
      errors = amount.errors + currency.errors
      return Result.new(nil, errors) unless errors.empty?

      Result.new(Money.from_amount(amount.value, currency.value), errors)
    end

    def resolve_currency(input, strict:, path:)
      return Result.ok(@fixed_currency) if @fixed_currency

      @currency.resolve(input, strict:, path:)
    end

    # A Decimal whose scale matches the resolved currency's subunit precision
    # (USD → 2, JPY → 0, BHD → 3), so excess precision is rejected per currency.
    # Falls back to the default scale when the currency couldn't be determined.
    def amount_field(currency)
      scale = currency.value ? Money::Currency.find(currency.value).exponent : Types::Decimal::DEFAULT_SCALE
      ScalarField.new(name: @amount_name, type: Types::Decimal.new(scale:, round: @round), required: true)
    end

    def nested_shape_error(raw, strict:, path:)
      raise CoercionError.new(code: :invalid_object, input: raw) if strict

      Result.failed(build_error(path: path + [name], code: :invalid_object, input: raw))
    end

    def amount_key(override)
      override || (@format == :nested ? :amount : name)
    end

    def currency_key(override)
      override || (@format == :nested ? :currency : :"#{name}_currency")
    end
  end
end
