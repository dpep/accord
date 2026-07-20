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
  #   money :salary, currency: "USD"                 # fixed currency; amount only (a conflicting currency errors)
  #   money :salary, default_currency: "USD"         # currency optional, defaults to USD, input overrides
  #   money :salary, format: :flat, currency_field: :ccy   # aliased currency key
  #
  # A default currency (per-field `default_currency:` or the global
  # `Accord.config.default_currency`) makes the currency optional and
  # polymorphic: a bare amount is that currency, and an explicit currency
  # overrides. `currency:` (fixed) instead locks the currency; input may omit it
  # or match it, but a conflicting currency is rejected (`:currency_mismatch`).
  #
  # Dump always emits the canonical nested { amount:, currency: } form,
  # regardless of the input format.
  class MoneyField < Field
    FORMATS = %i[nested flat].freeze

    # The canonical GraphQL input type for money — its dump shape, regardless of
    # the wire format declared on the field.
    GRAPHQL_INPUT_NAME = "MoneyInput"
    GRAPHQL_INPUT = "input MoneyInput {\n  amount: String!\n  currency: String!\n}"

    # Declarative config, introspectable like every other field: the wire
    # `format` (:nested/:flat), a locked `fixed_currency` (or nil), and the
    # field-level `default_currency` (or nil — the global default isn't part of
    # the field's own declaration).
    attr_reader :format, :fixed_currency

    def round?
      @round
    end

    def default_currency
      @field_default_currency
    end

    def initialize(format: :nested, currency: nil, default_currency: nil, round: false,
                   amount_field: nil, currency_field: nil, **opts)
      super(**opts)
      Accord.require_money!
      raise ArgumentError, "unknown money format: #{format.inspect}" unless FORMATS.include?(format)

      @format = format
      @round = round
      @amount_type = Types::Decimal.new # representative instance for OpenAPI (scale-independent)
      @currency_type = Types::ISOCurrency.new
      @fixed_currency = currency ? @currency_type.parse!(currency) : nil
      @field_default_currency = default_currency ? @currency_type.parse!(default_currency) : nil
      @amount_name = amount_key(amount_field)
      # Currency is always optional at the component level; required-when-no-default
      # is enforced in #resolve_currency so the global default can apply.
      @currency = ScalarField.new(name: currency_key(currency_field), type: @currency_type)
    end

    # Resolve against the full input — flat format sources the amount and
    # currency from sibling keys, so the base #read (which reads a single key)
    # doesn't fit. Presence/default/required policy mirrors the base template.
    def resolve(input, strict:, path:)
      present, raw = read(input)
      resolve_absent(present, raw, strict:, path:) || coerce_money(input, raw, strict:, path:)
    end

    def dump(value)
      return if value.nil?

      {
        amount: Types::Decimal.new(scale: value.currency.exponent).dump(value.amount),
        currency: @currency_type.dump(value.currency.iso_code),
      }
    end

    # The canonical (nested) money object — its dump shape and the MoneyInput
    # GraphQL component. The wire projection routes through #openapi_properties,
    # which differs for the flat format.
    def openapi
      {
        type: "object",
        properties: { amount: @amount_type.openapi, currency: currency_openapi },
        required: %i[amount currency],
      }
    end

    # Nested money is one object property; flat money is two sibling keys on the
    # parent (`salary` + `salary_currency`), so document it as such.
    def openapi_properties
      return { name => openapi } if @format == :nested

      { @amount_name => @amount_type.openapi, @currency.name => currency_openapi }
    end

    # The currency key is required only when the caller must supply it — not when
    # it's fixed or defaulted.
    def openapi_required_keys
      return [] unless required?
      return [name] if @format == :nested

      keys = [@amount_name]
      keys << @currency.name unless @fixed_currency || effective_default_currency
      keys
    end

    def rbs
      "Money"
    end

    def sorbet
      "Money"
    end

    def graphql_ref
      GRAPHQL_INPUT_NAME
    end

    def graphql_schemas(into)
      into[GRAPHQL_INPUT_NAME] ||= GRAPHQL_INPUT
    end

    private

    # The currency property schema: a fixed enum, else the ISO-currency schema.
    def currency_openapi
      @fixed_currency ? { type: "string", enum: [@fixed_currency] } : @currency_type.openapi
    end

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

      money = Money.from_amount(amount.value, currency.value)
      Result.new(money, validate_value(money, path))
    end

    def resolve_currency(input, strict:, path:)
      return resolve_fixed_currency(input, strict:, path:) if @fixed_currency

      result = @currency.resolve(input, strict:, path:)
      # Present (valid or invalid) input wins — an explicit currency overrides.
      return result unless result.value.nil? && result.errors.empty?

      # Absent: fall back to the default currency, else the currency is required.
      default = effective_default_currency
      return Result.ok(default) if default
      raise MissingField, @currency.name if strict

      currency_path = path + [@currency.name]
      Accord.notify(:required, field: @currency.name, path: currency_path)
      Result.failed(Error.new(path: currency_path, field: @currency.name, code: :required))
    end

    # A fixed currency locks the value, but an input that supplies a *different*
    # currency is a contract violation, not something to silently drop. Absent or
    # matching input is fine; a conflicting one errors.
    def resolve_fixed_currency(input, strict:, path:)
      present, raw = @currency.read(input)
      return Result.ok(@fixed_currency) unless present && !raw.nil?
      return Result.ok(@fixed_currency) if @currency_type.parse(raw) == @fixed_currency

      raise CoercionError.new(code: :currency_mismatch, input: raw) if strict

      currency_path = path + [@currency.name]
      Accord.notify(:currency_mismatch, field: @currency.name, path: currency_path, input: raw)
      Result.failed(Error.new(path: currency_path, field: @currency.name, code: :currency_mismatch,
                              input: raw, expected: @fixed_currency))
    end

    # The currency actually applied when input omits one: the field default, else
    # the global default. (The declared field default alone is the public
    # #default_currency reader.)
    def effective_default_currency
      return @field_default_currency if @field_default_currency

      configured = Accord.config.default_currency
      configured && @currency_type.parse!(configured)
    end

    # A Decimal whose scale matches the resolved currency's subunit precision
    # (USD → 2, JPY → 0, BHD → 3), so excess precision is rejected per currency.
    # Falls back to the default scale when the currency couldn't be determined.
    # Cached per scale — there are only a handful — so a parse doesn't rebuild a
    # ScalarField + Decimal every time.
    def amount_field(currency)
      scale = currency.value ? Money::Currency.find(currency.value).exponent : Types::Decimal::DEFAULT_SCALE
      (@amount_fields ||= {})[scale] ||=
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
