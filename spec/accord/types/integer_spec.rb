# frozen_string_literal: true

RSpec.describe Accord::Types::Integer do
  subject(:type) { described_class.new }

  describe "accepted inputs" do
    it "passes integers through" do
      expect(type.parse!(42)).to eq(42)
    end

    it "coerces integer-valued strings when permissive" do
      expect(type.parse("42")).to eq(42)
      expect(type.parse("-5")).to eq(-5)
    end

    it "coerces whole Floats when permissive" do
      expect(type.parse(42.0)).to eq(42)
    end
  end

  describe "rejected inputs" do
    it "raises in strict mode for non-integers" do
      expect { type.parse!("42") }.to raise_error(Accord::CoercionError)
      expect { type.parse!(42.0) }.to raise_error(Accord::CoercionError)
    end

    it "rejects non-integer strings and fractional Floats" do
      expect(type.parse("4.5")).to be_nil
      expect(type.parse(4.5)).to be_nil
    end

    it "rejects non-finite Floats without raising" do
      expect(type.parse(Float::INFINITY)).to be_nil
      expect(type.parse(Float::NAN)).to be_nil
    end
  end

  describe "#openapi" do
    it "describes an integer" do
      expect(type.openapi).to eq(type: "integer")
    end
  end
end
