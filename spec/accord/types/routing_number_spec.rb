# frozen_string_literal: true

describe Accord::Types::RoutingNumber do
  subject(:type) { described_class.new }

  describe "accepted inputs" do
    it "accepts a checksum-valid routing number" do
      expect(type.parse!("021000021")).to eq("021000021")   # JPMorgan Chase
      expect(type.parse!("011401533")).to eq("011401533")
    end

    it "strips formatting" do
      expect(type.parse!("0210-00021")).to eq("021000021")
    end
  end

  describe "rejected inputs" do
    it "rejects a bad checksum" do
      expect(type.parse("021000022")).to be_nil
    end

    it "rejects the wrong number of digits" do
      expect(type.parse("12345")).to be_nil
      expect { type.parse!("nope") }.to raise_error(Accord::CoercionError)
    end
  end

  describe "#openapi" do
    it "describes an aba routing number string" do
      expect(type.openapi).to eq(type: "string", format: "aba-routing-number", example: "021000021")
    end
  end
end
