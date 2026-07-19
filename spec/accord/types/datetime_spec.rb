# frozen_string_literal: true

require "time"

RSpec.describe Accord::Types::DateTime do
  subject(:type) { described_class.new }

  describe "accepted inputs" do
    it "passes Time through" do
      time = Time.utc(2026, 1, 15, 9, 30)
      expect(type.parse!(time)).to eq(time)
    end

    it "parses ISO-8601 strings, preserving time-of-day" do
      parsed = type.parse!("2026-01-15T09:30:00Z")
      expect(parsed).to be_a(Time)
      expect(parsed.getutc.hour).to eq(9)
    end

    it "converts DateTime to Time" do
      expect(type.parse!(DateTime.new(2026, 1, 15, 9, 30))).to be_a(Time)
    end
  end

  describe "legacy formats (permissive only)" do
    subject(:type) { described_class.new(formats: ["%m/%d/%Y %H:%M"]) }

    it "parses a configured legacy format" do
      expect(type.parse("01/15/2026 09:30")).to be_a(Time)
    end

    it "does not accept legacy formats in strict mode" do
      expect { type.parse!("01/15/2026 09:30") }.to raise_error(Accord::CoercionError)
    end
  end

  describe "rejected inputs" do
    it "raises in strict mode for garbage" do
      expect { type.parse!("not a time") }.to raise_error(Accord::CoercionError)
    end

    it "returns nil in permissive mode for garbage" do
      expect(type.parse("not a time")).to be_nil
    end
  end

  describe "#dump" do
    it "emits an ISO-8601 string" do
      expect(type.dump(Time.utc(2026, 1, 15, 9, 30, 0))).to eq("2026-01-15T09:30:00Z")
    end
  end

  describe "#openapi" do
    it "describes a date-time string" do
      expect(type.openapi).to eq(type: "string", format: "date-time")
    end
  end
end
