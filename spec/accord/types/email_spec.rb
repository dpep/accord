# frozen_string_literal: true

describe Accord::Types::Email do
  subject(:type) { described_class.new }

  describe "accepted inputs" do
    it "canonicalizes to lowercase" do
      expect(type.parse!("Ada@Example.COM")).to eq("ada@example.com")
    end

    it "strips surrounding whitespace" do
      expect(type.parse!("  ada@example.com  ")).to eq("ada@example.com")
    end
  end

  describe "rejected inputs" do
    it "raises in strict mode for a malformed address" do
      expect { type.parse!("not-an-email") }.to raise_error(Accord::CoercionError)
    end

    it "returns nil in permissive mode for garbage" do
      expect(type.parse("nope@")).to be_nil
    end
  end

  describe "#openapi" do
    it "describes an email string" do
      expect(type.openapi).to eq(type: "string", format: "email")
    end
  end
end
