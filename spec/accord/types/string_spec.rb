# frozen_string_literal: true

describe Accord::Types::String do
  subject(:type) { described_class.new }

  describe "accepted inputs" do
    it "passes strings through" do
      expect(type.parse!("hi")).to eq("hi")
    end

    it "coerces symbols and numbers when permissive" do
      expect(type.parse(:hi)).to eq("hi")
      expect(type.parse(42)).to eq("42")
    end
  end

  describe "rejected inputs" do
    it "raises in strict mode for non-strings" do
      expect { type.parse!(42) }.to raise_error(Accord::CoercionError)
    end

    it "returns nil in permissive mode for un-coercible values" do
      expect(type.parse([1, 2])).to be_nil
    end
  end

  describe "nil" do
    it "is passed through, not coerced" do
      expect(type.parse!(nil)).to be_nil
    end
  end

  describe "#openapi" do
    it "describes a string" do
      expect(type.openapi).to eq(type: "string")
    end
  end
end
