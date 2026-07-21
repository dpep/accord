# frozen_string_literal: true

describe Accord::Types::PostalCode do
  describe "US (default)" do
    subject(:type) { described_class.new }

    it "canonicalizes ZIP and ZIP+4" do
      expect(type.parse!("12345")).to eq("12345")
      expect(type.parse!("123456789")).to eq("12345-6789")
    end

    it "rejects the non-standard space form and bad input" do
      expect(type.parse("12345 6789")).to be_nil
      expect(type.parse("abcde")).to be_nil
    end

    it "reports the country" do
      expect(type.country).to eq(:us)
    end
  end

  describe "Canada" do
    subject(:type) { described_class.new(country: :ca) }

    it "canonicalizes to the uppercase, single-spaced form" do
      expect(type.parse!("K1A 0B1")).to eq("K1A 0B1")
      expect(type.parse!("k1a0b1")).to eq("K1A 0B1")
    end

    it "rejects an invalid first-position letter and bad shape" do
      expect(type.parse("D1A 1A1")).to be_nil    # D is not a valid first letter
      expect(type.parse("12345")).to be_nil
    end

    it "describes a Canadian example in OpenAPI" do
      expect(type.openapi).to eq(type: "string", format: "postal-code", example: "A1A 1A1")
    end
  end

  it "rejects an unsupported country at declaration" do
    expect { described_class.new(country: :xx) }.to raise_error(ArgumentError, /unsupported/)
  end
end
