# frozen_string_literal: true

RSpec.describe Accord::Types::IPAddress do
  subject(:type) { described_class.new }

  describe "accepted inputs" do
    it "accepts IPv4" do
      expect(type.parse!("192.168.1.1")).to eq("192.168.1.1")
    end

    it "canonicalizes IPv6 (lowercase + compressed)" do
      expect(type.parse!("2001:DB8:0:0:0:0:0:1")).to eq("2001:db8::1")
    end
  end

  describe "rejected inputs" do
    it "raises in strict mode for an invalid address" do
      expect { type.parse!("999.1.1.1") }.to raise_error(Accord::CoercionError)
    end

    it "returns nil in permissive mode for garbage" do
      expect(type.parse("not an ip")).to be_nil
    end
  end

  describe "#openapi" do
    it "describes an ip string" do
      expect(type.openapi).to eq(type: "string", format: "ip")
    end
  end
end
