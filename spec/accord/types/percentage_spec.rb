# frozen_string_literal: true

require "bigdecimal"

describe Accord::Types::Percentage do
  subject(:type) { described_class.new }

  it "is a Decimal defaulting to scale 2" do
    expect(type).to be_a(Accord::Types::Decimal)
    expect(type.scale).to eq(2)
  end

  it "parses to BigDecimal and dumps canonically" do
    expect(type.parse!("12.5")).to eq(BigDecimal("12.5"))
    expect(type.dump(BigDecimal("12.5"))).to eq("12.50")
  end

  describe "% stripping" do
    it "strips a % sign when permissive" do
      expect(type.parse("50%")).to eq(BigDecimal("50"))
    end

    it "rejects a % sign in strict mode" do
      expect { type.parse!("50%") }.to raise_error(Accord::CoercionError)
    end
  end

  describe "#openapi" do
    it "is a decimal string tagged as a percentage" do
      expect(type.openapi).to eq(type: "string", format: "percentage")
    end
  end
end
