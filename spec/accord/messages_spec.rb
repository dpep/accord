# frozen_string_literal: true

require "accord/i18n"

RSpec.describe Accord::Messages do
  let(:schema) do
    Class.new(Accord::Schema) do
      string :name, :required
      integer :hire_count do
        min 18
      end
    end
  end

  around do |example|
    previous = I18n.locale
    I18n.locale = :en
    example.run
    I18n.locale = previous
  end

  describe ".message" do
    it "translates a code, interpolating metadata" do
      error = schema.parse({ hire_count: "5" }).errors.find { |e| e.code == :too_small }
      expect(described_class.message(error)).to eq("must be at least 18")
    end

    it "falls back to the code for unknown (custom) codes" do
      error = Accord::Error.new(path: [:x], code: :totally_custom)
      expect(described_class.message(error)).to eq("totally_custom")
    end
  end

  describe ".full_message" do
    it "prepends the humanized field" do
      error = schema.parse({}).errors.find { |e| e.field == :name }
      expect(described_class.full_message(error)).to eq("Name is required")
    end
  end

  describe ".messages" do
    it "groups field-less messages by field (like errors.messages)" do
      expect(described_class.messages(schema.parse({ hire_count: "5" }).errors))
        .to eq(name: ["is required"], hire_count: ["must be at least 18"])
    end
  end

  describe ".full_messages" do
    it "returns full messages (like errors.full_messages)" do
      expect(described_class.full_messages(schema.parse({ hire_count: "5" }).errors))
        .to contain_exactly("Name is required", "Hire count must be at least 18")
    end
  end
end
