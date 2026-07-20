# frozen_string_literal: true

describe Accord::Types::ISOCurrency do
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
    it "documents the ISO-4217 format, not the full code enum" do
      schema = type.openapi
      expect(schema).to eq(type: "string", format: "iso-4217", example: "USD")
    end

    it "enumerates only the restricted set when a field narrows it with inclusion" do
      field = Class.new(Accord::Schema) { iso_currency(:ccy) { inclusion %w[USD MXN] } }.fields[:ccy]
      expect(field.openapi).to include(type: "string", format: "iso-4217", enum: %w[USD MXN])
    end
  end
end
