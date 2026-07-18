# frozen_string_literal: true

require "date"

RSpec.describe Accord::Types::Date do
  subject(:type) { described_class.new }

  describe "accepted inputs" do
    it "passes Date through" do
      date = Date.new(2026, 7, 17)
      expect(type.parse!(date)).to eq(date)
    end

    it "parses ISO-8601 strings in either mode" do
      expect(type.parse!("2026-07-17")).to eq(Date.new(2026, 7, 17))
      expect(type.parse("2026-07-17")).to eq(Date.new(2026, 7, 17))
    end

    it "converts Time to Date" do
      expect(type.parse!(Time.new(2026, 7, 17, 9, 30))).to eq(Date.new(2026, 7, 17))
    end
  end

  describe "legacy formats (permissive only)" do
    subject(:type) { described_class.new(formats: ["%m/%d/%Y"]) }

    it "parses a configured legacy format" do
      expect(type.parse("07/17/2026")).to eq(Date.new(2026, 7, 17))
    end

    it "does not accept legacy formats in strict mode" do
      expect { type.parse!("07/17/2026") }.to raise_error(Accord::CoercionError)
    end
  end

  describe "rejected inputs" do
    it "raises in strict mode for garbage" do
      expect { type.parse!("not a date") }.to raise_error(Accord::CoercionError)
    end

    it "returns nil in permissive mode for garbage" do
      expect(type.parse("not a date")).to be_nil
    end
  end

  describe "#dump" do
    it "emits an ISO-8601 string" do
      expect(type.dump(Date.new(2026, 7, 17))).to eq("2026-07-17")
    end
  end

  describe "#openapi" do
    it "describes a date-formatted string" do
      expect(type.openapi).to eq(type: "string", format: "date")
    end
  end
end
