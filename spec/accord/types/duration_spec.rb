# frozen_string_literal: true

require "bigdecimal"

RSpec.describe Accord::Types::Duration do
  subject(:type) { described_class.new }

  it "defaults to hours at scale 2" do
    expect(type.unit).to eq(:hours)
    expect(type.scale).to eq(2)
  end

  describe "accepted inputs" do
    it "always returns a BigDecimal" do
      expect(type.parse!("1.5")).to be_a(BigDecimal)
    end

    it "parses plain numbers" do
      expect(type.parse!("1")).to eq(BigDecimal("1"))
      expect(type.parse!("1.50")).to eq(BigDecimal("1.5"))
      expect(type.parse!(1)).to eq(BigDecimal("1"))
      expect(type.parse!(BigDecimal("1.25"))).to eq(BigDecimal("1.25"))
    end

    it "routes Float through its string form when permissive" do
      expect(type.parse(1.5)).to eq(BigDecimal("1.5"))
    end
  end

  describe "rejected inputs" do
    it "does not accept duration syntaxes like 1h or 01:30" do
      expect(type.parse("1h")).to be_nil
      expect(type.parse("01:30")).to be_nil
    end

    it "raises for non-numeric input in strict mode" do
      expect { type.parse!("1h") }.to raise_error(Accord::CoercionError)
    end
  end

  describe "scale enforcement" do
    subject(:type) { described_class.new(scale: 3) }

    it "accepts values within scale" do
      expect(type.parse!("1.250")).to eq(BigDecimal("1.25"))
      expect(type.parse!("0.125")).to eq(BigDecimal("0.125"))
    end

    it "raises for excess precision in strict mode" do
      expect { type.parse!("1.2345") }.to raise_error(Accord::CoercionError)
    end
  end

  describe "#dump" do
    it "renders exactly scale decimal places" do
      expect(type.dump(BigDecimal("1"))).to eq("1.00")
      expect(type.dump(BigDecimal("1.5"))).to eq("1.50")
    end

    it "honors a custom scale" do
      expect(described_class.new(scale: 3).dump(BigDecimal("1.25"))).to eq("1.250")
    end
  end

  describe "#openapi" do
    it "describes a decimal duration in the configured unit" do
      expect(described_class.new(unit: :minutes).openapi).to eq(
        type: "string", format: "decimal", description: "Duration in minutes", example: "1.50",
      )
    end

    it "reflects each unit" do
      expect(described_class.new(unit: :hours).openapi[:description]).to eq("Duration in hours")
      expect(described_class.new(unit: :seconds).openapi[:description]).to eq("Duration in seconds")
    end
  end

  it "rejects an unknown unit at construction" do
    expect { described_class.new(unit: :fortnights) }.to raise_error(ArgumentError)
  end
end
