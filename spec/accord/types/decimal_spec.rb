# frozen_string_literal: true

require "bigdecimal"

RSpec.describe Accord::Types::Decimal do
  subject(:type) { described_class.new(scale: 4) }

  describe "accepted inputs" do
    it "always returns a BigDecimal" do
      expect(type.parse!("12.34")).to be_a(BigDecimal)
    end

    it "parses strings, integers, and BigDecimals" do
      expect(type.parse!("12.3456")).to eq(BigDecimal("12.3456"))
      expect(type.parse!(12)).to eq(BigDecimal("12"))
      expect(type.parse!(BigDecimal("12.34"))).to eq(BigDecimal("12.34"))
    end

    it "routes Float through its string form when permissive" do
      expect(type.parse(12.34)).to eq(BigDecimal("12.34"))
    end

    it "rejects Float in strict mode" do
      expect { type.parse!(12.34) }.to raise_error(Accord::CoercionError)
    end

    it "rejects non-numeric strings" do
      expect { type.parse!("abc") }.to raise_error(Accord::CoercionError)
    end
  end

  describe "scale enforcement" do
    subject(:type) { described_class.new(scale: 2) }

    it "accepts values within scale, padding shorter input" do
      expect(type.parse!("12.30")).to eq(BigDecimal("12.30"))
      expect(type.parse!("12")).to eq(BigDecimal("12.00"))
    end

    it "raises for excess precision in strict mode" do
      expect { type.parse!("12.345") }.to raise_error(Accord::CoercionError)
    end

    it "does not silently round in permissive mode" do
      expect(type.parse("12.345")).to be_nil
    end

    context "with round: true" do
      subject(:type) { described_class.new(scale: 2, round: true) }

      it "rounds excess precision instead of rejecting" do
        expect(type.parse!("12.345")).to eq(BigDecimal("12.35"))
      end
    end
  end

  describe "#dump" do
    subject(:type) { described_class.new(scale: 2) }

    it "renders exactly scale decimal places" do
      expect(type.dump(BigDecimal("12"))).to eq("12.00")
      expect(type.dump(BigDecimal("12.3"))).to eq("12.30")
      expect(type.dump(BigDecimal("12.34"))).to eq("12.34")
    end
  end

  describe "#openapi" do
    it "describes a decimal string" do
      expect(type.openapi).to eq(type: "string", format: "decimal")
    end
  end
end
