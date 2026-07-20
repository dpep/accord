# frozen_string_literal: true

RSpec.describe Accord::Types::UUID do
  subject(:type) { described_class.new }

  let(:canonical) { "550e8400-e29b-41d4-a716-446655440000" }

  describe "accepted inputs" do
    it "returns a canonical lowercase string" do
      expect(type.parse!(canonical)).to eq(canonical)
    end

    it "normalizes uppercase input" do
      expect(type.parse!("550E8400-E29B-41D4-A716-446655440000")).to eq(canonical)
    end
  end

  describe "rejected inputs" do
    it "raises in strict mode for an invalid UUID" do
      expect { type.parse!("not-a-uuid") }.to raise_error(Accord::CoercionError)
    end

    it "rejects UUIDs without hyphens" do
      expect { type.parse!("550e8400e29b41d4a716446655440000") }
        .to raise_error(Accord::CoercionError)
    end

    it "returns nil in permissive mode for garbage" do
      expect(type.parse("nope")).to be_nil
    end
  end

  describe "#dump" do
    it "emits the canonical lowercase UUID" do
      expect(type.dump("550E8400-E29B-41D4-A716-446655440000")).to eq(canonical)
    end
  end

  describe "#openapi" do
    it "describes a uuid-formatted string" do
      expect(type.openapi).to eq(type: "string", format: "uuid", example: canonical)
    end
  end

  describe "version option" do
    it "reads the configured version" do
      expect(described_class.new(version: 7).version).to eq(7)
    end

    it "accepts a UUID of the required version" do
      expect(described_class.new(version: 4).parse!(canonical)).to eq(canonical)  # canonical is v4
    end

    it "rejects a UUID of a different version" do
      expect { described_class.new(version: 7).parse!(canonical) }.to raise_error(Accord::CoercionError)
    end
  end
end
