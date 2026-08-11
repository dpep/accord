# frozen_string_literal: true

describe Accord::Types::BIC do
  subject(:type) { described_class.new }

  describe "accepted inputs" do
    it "canonicalizes to uppercase, no spaces" do
      expect(type.parse!("deutdeff")).to eq("DEUTDEFF")
      expect(type.parse!("NEDS ZA JJ XXX")).to eq("NEDSZAJJ")
    end

    it "drops a primary-office branch code so both forms round-trip alike" do
      expect(type.parse!("DEUTDEFFXXX")).to eq(type.parse!("DEUTDEFF"))
    end

    it "keeps a real branch code" do
      expect(type.parse!("DEUTDEFF500")).to eq("DEUTDEFF500")
    end

    it "keeps an 8-character code whose location code ends in XXX" do
      expect(type.parse!("ABCDXXXX")).to eq("ABCDXXXX")
    end
  end

  describe "rejected inputs" do
    it "rejects the wrong length" do
      expect(type.parse("DEUTDEF")).to be_nil      # 7
      expect(type.parse("DEUTDEFF5")).to be_nil    # 9
      expect { type.parse!("nope") }.to raise_error(Accord::CoercionError)
    end

    it "rejects digits in the institution and country codes" do
      expect(type.parse("DEU7DEFF")).to be_nil
      expect(type.parse("DEUTD3FF")).to be_nil
    end
  end

  describe "#openapi" do
    it "describes a bic string" do
      expect(type.openapi).to eq(type: "string", format: "bic", example: "DEUTDEFF")
    end
  end
end
