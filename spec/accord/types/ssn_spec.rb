# frozen_string_literal: true

describe Accord::Types::SSN do
  subject(:type) { described_class.new }

  describe "accepted inputs" do
    it "canonicalizes to the hyphenated form" do
      expect(type.parse!("123-45-6789")).to eq("123-45-6789")
      expect(type.parse!("123456789")).to eq("123-45-6789")
    end
  end

  describe "rejected inputs" do
    it "rejects bad length" do
      expect(type.parse("12345")).to be_nil
    end

    it "rejects structurally-invalid numbers" do
      expect(type.parse("000-45-6789")).to be_nil   # area 000
      expect(type.parse("666-45-6789")).to be_nil   # area 666
      expect(type.parse("900-45-6789")).to be_nil   # area >= 900
      expect(type.parse("123-00-6789")).to be_nil   # group 00
      expect(type.parse("123-45-0000")).to be_nil   # serial 0000
    end
  end

  describe "#openapi" do
    it "describes an ssn string" do
      expect(type.openapi).to eq(type: "string", format: "ssn", example: "123-45-6789")
    end
  end
end
