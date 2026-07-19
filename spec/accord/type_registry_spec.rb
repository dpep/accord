# frozen_string_literal: true

RSpec.describe "type registry" do
  it "registers the built-ins and generates a DSL method for each" do
    expect(Accord::Types.registered?(:currency)).to be(true)
    expect(Accord::Schema).to respond_to(:currency, :datetime, :uuid)
  end

  it "lets you add a custom semantic type, usable in the DSL immediately" do
    shout_type = Class.new(Accord::Types::String) do
      private

      def canonicalize(string, strict:) # rubocop:disable Lint/UnusedMethodArgument
        string.upcase
      end
    end
    stub_const("ShoutString", shout_type)
    Accord::Types.register(:shout, ShoutString)

    schema = Class.new(Accord::Schema) do
      shout :code
    end
    expect(schema.parse({ code: "abc" }).code).to eq("ABC")
  end

  it "lets you override a built-in type; schemas defined afterward use it" do
    on_off = Class.new(Accord::Types::Boolean) do
      private

      def coerce(value, strict:)
        return true if value == "on"
        return false if value == "off"

        super
      end
    end
    stub_const("OnOffBoolean", on_off)
    Accord::Types.register(:boolean, OnOffBoolean)

    schema = Class.new(Accord::Schema) do
      boolean :active
    end
    expect(schema.parse({ active: "on" }).active).to be(true)   # custom behavior
    expect(schema.parse({ active: "yes" }).active).to be(true)  # inherited base behavior
  ensure
    Accord::Types.register(:boolean, Accord::Types::Boolean) # restore the built-in
  end

  it "forwards type options to the constructor and keeps field options on the field" do
    schema = Class.new(Accord::Schema) do
      decimal :rate, :required, scale: 4
    end

    expect(schema.fields[:rate].type.scale).to eq(4)   # scale -> type
    expect(schema.fields[:rate].required?).to be(true) # required -> field
  end

  describe "inline keyword validators" do
    it "turns a registered validator keyword into a validator" do
      schema = Class.new(Accord::Schema) do
        string :name, format: /\A\w+\z/
      end

      expect(schema.parse({ name: "ok" })).to be_valid
      expect(schema.parse({ name: "no spaces" })).not_to be_valid
    end

    it "composes field options, type options, and validator keywords" do
      schema = Class.new(Accord::Schema) do
        decimal :price, :required, scale: 2, between: 0..100
      end
      field = schema.fields[:price]

      expect(field.type.scale).to eq(2)                                  # type option
      expect(field.required?).to be(true)                               # field option
      expect(field.validators.any?(Accord::Validators::Between)).to be(true) # validator keyword
    end

    it "feeds validator keywords into the OpenAPI projection" do
      schema = Class.new(Accord::Schema) do
        string :name, length: 1..50
      end

      expect(schema.fields[:name].openapi).to include(minLength: 1, maxLength: 50)
    end
  end
end
