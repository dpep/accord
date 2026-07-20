# frozen_string_literal: true

require "bigdecimal"

describe Accord::Types::Currency do
  subject(:type) { described_class.new }

  it "defaults to scale 2" do
    expect(type.scale).to eq(2)
  end

  describe "accepted inputs" do
    it "always returns a BigDecimal, never a Float" do
      expect(type.parse!("12.00")).to be_a(BigDecimal)
    end

    it "parses plain numeric strings, integers, and BigDecimals" do
      expect(type.parse!("12")).to eq(BigDecimal("12"))
      expect(type.parse!("12.00")).to eq(BigDecimal("12"))
      expect(type.parse!(12)).to eq(BigDecimal("12"))
      expect(type.parse!(BigDecimal("12.34"))).to eq(BigDecimal("12.34"))
    end

    it "strips a leading $, thousands commas, and surrounding whitespace" do
      expect(type.parse("$12.00")).to eq(BigDecimal("12"))
      expect(type.parse("1,234.56")).to eq(BigDecimal("1234.56"))
      expect(type.parse("$1,234.56")).to eq(BigDecimal("1234.56"))
      expect(type.parse("$ 1234")).to eq(BigDecimal("1234"))
      expect(type.parse("  $5  ")).to eq(BigDecimal("5"))
      expect(type.parse("-5")).to eq(BigDecimal("-5"))
    end
  end

  describe "rejected inputs" do
    it "raises in strict mode for non-numeric strings" do
      expect { type.parse!("$abc") }.to raise_error(Accord::CoercionError)
    end

    it "rejects currency formatting in strict mode" do
      expect { type.parse!("$12.00") }.to raise_error(Accord::CoercionError)
    end

    it "returns nil in permissive mode for garbage" do
      expect(type.parse("$abc")).to be_nil
    end

    it "rejects a $ or whitespace anywhere but the front" do
      expect(type.parse("1$234")).to be_nil    # $ in the middle
      expect(type.parse("12 34")).to be_nil    # interior whitespace
      expect(type.parse("$$5")).to be_nil      # doubled symbol
      expect(type.parse("5$")).to be_nil       # trailing symbol
      expect(type.parse("%5")).to be_nil       # wrong symbol
      expect(type.parse("$")).to be_nil        # symbol, no amount
    end
  end

  describe "scale enforcement" do
    it "raises for more than two decimal places in strict mode" do
      expect { type.parse!("12.345") }.to raise_error(Accord::CoercionError)
    end

    it "honors a custom scale" do
      expect(described_class.new(scale: 4).parse!("12.3456")).to eq(BigDecimal("12.3456"))
    end
  end

  describe "#dump" do
    it "renders exactly two decimal places" do
      expect(type.dump(BigDecimal("12"))).to eq("12.00")
      expect(type.dump(BigDecimal("12.3"))).to eq("12.30")
      expect(type.dump(BigDecimal("12.34"))).to eq("12.34")
    end
  end

  describe "#openapi" do
    it "exposes a decimal string with an example" do
      expect(type.openapi).to eq(type: "string", format: "decimal", example: "1234.56")
    end
  end
end
