# frozen_string_literal: true

describe Accord::Types::EIN do
  subject(:type) { described_class.new }

  describe "accepted inputs" do
    it "canonicalizes to the hyphenated XX-XXXXXXX form" do
      expect(type.parse!("12-3456789")).to eq("12-3456789")
      expect(type.parse!("123456789")).to eq("12-3456789")
    end
  end

  describe "rejected inputs" do
    it "rejects the wrong number of digits" do
      expect(type.parse("12345")).to be_nil
      expect { type.parse!("nope") }.to raise_error(Accord::CoercionError)
    end
  end

  describe "#openapi" do
    it "describes an ein string" do
      expect(type.openapi).to eq(type: "string", format: "ein", example: "12-3456789")
    end
  end
end
