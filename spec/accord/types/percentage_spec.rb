# frozen_string_literal: true

require "bigdecimal"

RSpec.describe Accord::Types::Percentage do
  subject(:type) { described_class.new }

  it "is a Decimal defaulting to scale 2" do
    expect(type).to be_a(Accord::Types::Decimal)
    expect(type.scale).to eq(2)
  end

  it "parses to BigDecimal and dumps canonically" do
    expect(type.parse!("12.5")).to eq(BigDecimal("12.5"))
    expect(type.dump(BigDecimal("12.5"))).to eq("12.50")
  end

  describe "#openapi" do
    it "is a decimal string tagged as a percentage" do
      expect(type.openapi).to eq(type: "string", format: "percentage")
    end
  end
end
