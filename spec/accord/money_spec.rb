# frozen_string_literal: true

require "money"

RSpec.describe "money type" do
  let(:usd) { Money.from_amount(BigDecimal("1234.50"), "USD") }

  describe "nested wire format (default)" do
    let(:schema) do
      Class.new(Accord::Schema) do
        money :salary
      end
    end

    it "parses { amount:, currency: } into a Money, canonicalizing the currency" do
      input = schema.parse({ salary: { amount: "1234.50", currency: "usd" } })

      expect(input).to be_valid
      expect(input.salary).to eq(usd)
    end

    it "leaves an optional absent money nil" do
      expect(schema.parse({}).salary).to be_nil
    end

    it "reports an invalid amount at the nested path — no special cases" do
      input = schema.parse({ salary: { amount: "abc", currency: "USD" } })

      expect(input).not_to be_valid
      expect(input.errors.map(&:path)).to include([:salary, :amount])
    end

    it "reports an invalid currency at the nested path" do
      input = schema.parse({ salary: { amount: "10.00", currency: "nope" } })

      expect(input.errors.map(&:path)).to include([:salary, :currency])
    end

    it "requires both components within a present money value" do
      input = schema.parse({ salary: { amount: "10.00" } })

      expect(input.errors.map(&:path)).to include([:salary, :currency])
    end

    it "raises in strict mode on invalid nested input" do
      expect { schema.parse({ salary: { amount: "abc", currency: "USD" } }, strict: true) }
        .to raise_error(Accord::CoercionError)
    end
  end

  describe "currency-aware amount scale" do
    let(:schema) do
      Class.new(Accord::Schema) do
        money :salary
      end
    end

    it "enforces the amount precision from the currency (USD → 2)" do
      input = schema.parse({ salary: { amount: "1234.567", currency: "USD" } })

      expect(input).not_to be_valid
      expect(input.errors.map(&:path)).to include([:salary, :amount])
    end

    it "accepts the precision the currency allows (BHD → 3)" do
      input = schema.parse({ salary: { amount: "1.234", currency: "BHD" } })

      expect(input).to be_valid
      expect(input.salary).to eq(Money.from_amount(BigDecimal("1.234"), "BHD"))
    end

    it "rejects fractional units a zero-decimal currency lacks (JPY → 0)" do
      input = schema.parse({ salary: { amount: "1234.5", currency: "JPY" } })

      expect(input.errors.map(&:path)).to include([:salary, :amount])
    end

    it "accepts whole amounts for zero-decimal currencies" do
      input = schema.parse({ salary: { amount: "1234", currency: "JPY" } })

      expect(input.salary).to eq(Money.from_amount(BigDecimal("1234"), "JPY"))
    end

    it "raises in strict mode when the amount is too precise for the currency" do
      expect { schema.parse({ salary: { amount: "1234.5", currency: "JPY" } }, strict: true) }
        .to raise_error(Accord::CoercionError)
    end
  end

  describe "flat wire format" do
    let(:schema) do
      Class.new(Accord::Schema) do
        money :salary, format: :flat
      end
    end

    it "sources amount and currency from sibling keys" do
      input = schema.parse({ salary: "1234.50", salary_currency: "usd" })

      expect(input.salary).to eq(usd)
    end

    it "reports errors at the flat sibling paths" do
      input = schema.parse({ salary: "1234.50", salary_currency: "nope" })

      expect(input.errors.map(&:path)).to include([:salary_currency])
    end
  end

  describe "default currency" do
    it "makes currency optional with a per-field default, overridable by input" do
      schema = Class.new(Accord::Schema) { money :salary, default_currency: "USD" }

      expect(schema.parse({ salary: { amount: "10.00" } }).salary)
        .to eq(Money.from_amount(BigDecimal("10.00"), "USD"))
      expect(schema.parse({ salary: { amount: "10.00", currency: "EUR" } }).salary)
        .to eq(Money.from_amount(BigDecimal("10.00"), "EUR"))
    end

    it "honors a global default currency" do
      previous = Accord.config.default_currency
      Accord.configure { |c| c.default_currency = "USD" }
      schema = Class.new(Accord::Schema) { money :salary }

      expect(schema.parse({ salary: { amount: "10.00" } }).salary)
        .to eq(Money.from_amount(BigDecimal("10.00"), "USD"))
    ensure
      Accord.config.default_currency = previous
    end

    it "still requires currency when no default is set" do
      schema = Class.new(Accord::Schema) { money :salary }

      expect(schema.parse({ salary: { amount: "10.00" } }).errors.map(&:path))
        .to include([:salary, :currency])
    end

    it "reports an explicitly invalid currency rather than defaulting" do
      schema = Class.new(Accord::Schema) { money :salary, default_currency: "USD" }

      expect(schema.parse({ salary: { amount: "10.00", currency: "nope" } }).errors.map(&:path))
        .to include([:salary, :currency])
    end
  end

  describe "fixed currency" do
    let(:schema) do
      Class.new(Accord::Schema) do
        money :salary, currency: "USD"
      end
    end

    it "takes the currency from configuration, not input" do
      input = schema.parse({ salary: { amount: "1234.50" } })

      expect(input.salary).to eq(usd)
    end

    it "rejects an unknown fixed currency at declaration" do
      expect do
        Class.new(Accord::Schema) { money :salary, currency: "ZZ" }
      end.to raise_error(Accord::CoercionError)
    end
  end

  describe "aliased currency key" do
    let(:schema) do
      Class.new(Accord::Schema) do
        money :salary, format: :flat, currency_field: :ccy
      end
    end

    it "sources the currency from the aliased key" do
      input = schema.parse({ salary: "1234.50", ccy: "usd" })

      expect(input.salary).to eq(usd)
    end
  end

  describe "#dump" do
    it "emits the canonical nested representation" do
      field = Accord::MoneyField.new(name: :salary)

      expect(field.dump(usd)).to eq(amount: "1234.50", currency: "USD")
    end
  end

  describe "#openapi" do
    it "generates an object schema reusing the component scalar types" do
      schema = Accord::MoneyField.new(name: :salary).openapi

      expect(schema[:type]).to eq("object")
      expect(schema[:properties][:amount]).to eq(type: "string", format: "decimal")
      expect(schema[:properties][:currency][:enum]).to include("USD")
      expect(schema[:required]).to contain_exactly(:amount, :currency)
    end
  end

  describe "introspection" do
    it "exposes its declarative config like any other field" do
      field = Accord::MoneyField.new(name: :salary, format: :flat, currency: "usd", round: true)

      expect(field.format).to eq(:flat)
      expect(field.fixed_currency).to eq("USD")
      expect(field.round?).to be(true)
      expect(field.default_currency).to be_nil
    end

    it "reports the declared field-level default currency" do
      field = Accord::MoneyField.new(name: :salary, default_currency: "eur")

      expect(field.default_currency).to eq("EUR")
      expect(field.fixed_currency).to be_nil
    end
  end
end
