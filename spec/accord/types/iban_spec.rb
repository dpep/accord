# frozen_string_literal: true

describe Accord::Types::IBAN do
  subject(:type) { described_class.new }

  describe "accepted inputs" do
    it "canonicalizes the grouped form to uppercase, no spaces" do
      expect(type.parse!("GB82 WEST 1234 5698 7654 32")).to eq("GB82WEST12345698765432")
      expect(type.parse!("de89 3704 0044 0532 0130 00")).to eq("DE89370400440532013000")
    end
  end

  describe "rejected inputs" do
    it "rejects a bad mod-97 checksum" do
      expect(type.parse("GB82 WEST 1234 5698 7654 33")).to be_nil
    end

    it "rejects a malformed IBAN" do
      expect(type.parse("GB82")).to be_nil          # too short
      expect { type.parse!("nope") }.to raise_error(Accord::CoercionError)
    end
  end

  describe "#openapi" do
    it "describes an iban string" do
      expect(type.openapi).to eq(type: "string", format: "iban", example: "GB82WEST12345698765432")
    end
  end
end
