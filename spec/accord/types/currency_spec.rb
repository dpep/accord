# frozen_string_literal: true

require "bigdecimal"

RSpec.describe Accord::Types::Currency do
  subject(:type) { described_class.new }

  describe "accepted inputs" do
    it "always returns a BigDecimal, never a Float" do
      expect(type.parse!("10.50")).to be_a(BigDecimal)
    end

    it "parses plain numeric strings and integers in either mode" do
      expect(type.parse!("10")).to eq(BigDecimal("10"))
      expect(type.parse!("10.50")).to eq(BigDecimal("10.50"))
      expect(type.parse!(10)).to eq(BigDecimal("10"))
    end

    it "strips currency formatting when permissive" do
      expect(type.parse("$10.50")).to eq(BigDecimal("10.50"))
      expect(type.parse("1,000.00")).to eq(BigDecimal("1000.00"))
    end
  end

  describe "Float handling" do
    it "rejects Float in strict mode" do
      expect { type.parse!(10.5) }.to raise_error(Accord::CoercionError)
    end

    it "routes Float through its string form when permissive" do
      expect(type.parse(10.5)).to eq(BigDecimal("10.5"))
    end
  end

  describe "rejected inputs" do
    it "raises in strict mode for non-numeric strings" do
      expect { type.parse!("$abc") }.to raise_error(Accord::CoercionError)
    end

    it "rejects formatted input in strict mode" do
      expect { type.parse!("$10.50") }.to raise_error(Accord::CoercionError)
    end

    it "returns nil in permissive mode for garbage" do
      expect(type.parse("$abc")).to be_nil
    end
  end

  describe "#dump" do
    it "emits a plain decimal string" do
      expect(type.dump(BigDecimal("1000.5"))).to eq("1000.5")
    end
  end

  describe "#openapi" do
    it "describes a number" do
      expect(type.openapi).to eq(type: "number")
    end
  end
end
