# frozen_string_literal: true

describe Accord::Types::Boolean do
  subject(:type) { described_class.new }

  describe "strict" do
    it "accepts true and false" do
      expect(type.parse!(true)).to be(true)
      expect(type.parse!(false)).to be(false)
    end

    it "rejects string encodings" do
      expect { type.parse!("true") }.to raise_error(Accord::CoercionError)
    end
  end

  describe "permissive" do
    {
      "true" => true, "1" => true, "yes" => true, "YES" => true,
      "false" => false, "0" => false, "no" => false, " No " => false
    }.each do |input, expected|
      it "coerces #{input.inspect} to #{expected}" do
        expect(type.parse(input)).to be(expected)
      end
    end

    it "returns nil for un-coercible values" do
      expect(type.parse("maybe")).to be_nil
    end
  end

  describe "#openapi" do
    it "describes a boolean" do
      expect(type.openapi).to eq(type: "boolean")
    end
  end
end
