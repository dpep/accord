# frozen_string_literal: true

RSpec.describe Accord::Types::ISOCurrency do
  subject(:type) { described_class.new }

  describe "canonicalization" do
    it "uppercases the code" do
      expect(type.parse!("usd")).to eq("USD")
      expect(type.parse!("Usd")).to eq("USD")
      expect(type.parse!("USD")).to eq("USD")
    end
  end

  describe "rejected inputs" do
    it "raises in strict mode for an unknown code" do
      expect { type.parse!("ZZ") }.to raise_error(Accord::CoercionError)
    end

    it "returns nil in permissive mode for garbage" do
      expect(type.parse("nope")).to be_nil
    end
  end

  describe "#dump" do
    it "emits the uppercase code" do
      expect(type.dump("usd")).to eq("USD")
    end
  end

  describe "#openapi" do
    it "describes a string enum of ISO-4217 codes" do
      schema = type.openapi
      expect(schema[:type]).to eq("string")
      expect(schema[:enum]).to include("USD", "EUR", "GBP")
      expect(schema[:example]).to eq("USD")
    end
  end
end
