# frozen_string_literal: true

describe Accord::Types::ZipCode do
  subject(:type) { described_class.new }

  describe "accepted inputs" do
    it "accepts a 5-digit ZIP" do
      expect(type.parse!("12345")).to eq("12345")
    end

    it "canonicalizes ZIP+4 to the hyphenated form" do
      expect(type.parse!("12345-6789")).to eq("12345-6789")
      expect(type.parse!("123456789")).to eq("12345-6789")
    end
  end

  describe "rejected inputs" do
    it "rejects the wrong length, non-digits, or the non-standard space form" do
      expect(type.parse("1234")).to be_nil
      expect(type.parse("1234567")).to be_nil
      expect(type.parse("12345 6789")).to be_nil     # space-separated is not standard
      expect { type.parse!("abcde") }.to raise_error(Accord::CoercionError)
    end
  end

  describe "#openapi" do
    it "describes a zip-code string" do
      expect(type.openapi).to eq(type: "string", format: "zip-code", example: "12345")
    end
  end
end
