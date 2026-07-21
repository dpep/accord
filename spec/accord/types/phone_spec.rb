# frozen_string_literal: true

describe Accord::Types::Phone do
  subject(:type) { described_class.new }

  describe "accepted inputs" do
    it "canonicalizes common written forms to E.164" do
      %w[(555)123-4567 555-123-4567 555.123.4567 5551234567].each do |form|
        expect(type.parse!(form)).to eq("+15551234567")
      end
    end

    it "accepts a leading country code" do
      expect(type.parse!("1-555-123-4567")).to eq("+15551234567")
      expect(type.parse!("+1 555 123 4567")).to eq("+15551234567")
    end

    it "honors a configured country code (per-field and global default)" do
      expect(described_class.new(country_code: "44").parse!("445551234567")).to eq("+445551234567")

      Accord.config.default_phone_country_code = "44"
      expect(described_class.new.country_code).to eq("44")
    ensure
      Accord.config.default_phone_country_code = "1"
    end
  end

  describe "rejected inputs" do
    it "rejects the wrong number of digits" do
      expect(type.parse("12345")).to be_nil
      expect(type.parse("555123456789")).to be_nil
      expect { type.parse!("nope") }.to raise_error(Accord::CoercionError)
    end
  end

  describe "#openapi" do
    it "describes a phone string" do
      expect(type.openapi).to eq(type: "string", format: "phone", example: "+15551234567")
    end
  end
end
