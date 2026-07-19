# frozen_string_literal: true

RSpec.describe Accord::Types::URL do
  subject(:type) { described_class.new }

  describe "accepted inputs" do
    it "accepts http(s) URLs" do
      expect(type.parse!("https://example.com/path")).to eq("https://example.com/path")
    end

    it "canonicalizes scheme and host to lowercase, preserving the path" do
      expect(type.parse!("HTTPS://Example.COM/Path")).to eq("https://example.com/Path")
    end
  end

  describe "rejected inputs" do
    it "rejects non-http schemes" do
      expect { type.parse!("ftp://example.com") }.to raise_error(Accord::CoercionError)
    end

    it "rejects strings without a host" do
      expect { type.parse!("example.com") }.to raise_error(Accord::CoercionError)
    end

    it "returns nil in permissive mode for garbage" do
      expect(type.parse("not a url")).to be_nil
    end
  end

  describe "#openapi" do
    it "describes a uri string" do
      expect(type.openapi).to eq(type: "string", format: "uri")
    end
  end
end
