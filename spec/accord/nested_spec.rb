# frozen_string_literal: true

require "bigdecimal"

RSpec.describe "nested schemas" do
  let(:address) do
    Class.new(Accord::Schema) do
      string :city, required: true
      string :zip
    end
  end

  describe "object fields" do
    let(:schema) do
      addr = address
      Class.new(Accord::Schema) do
        string :name, required: true
        object :address, addr
      end
    end

    it "exposes the nested value as a schema instance" do
      input = schema.parse({ name: "Ada", address: { city: "Paris", zip: "75001" } })

      expect(input).to be_valid
      expect(input.address).to be_a(address)
      expect(input.address.city).to eq("Paris")
    end

    it "bubbles nested errors up with a prefixed path" do
      input = schema.parse({ name: "Ada", address: { zip: "75001" } })

      expect(input).not_to be_valid
      error = input.errors.find { |e| e.code == :required }
      expect(error.path).to eq([:address, :city])
    end

    it "leaves an optional absent object nil" do
      input = schema.parse({ name: "Ada" })
      expect(input.address).to be_nil
    end

    it "reports a non-hash value as an invalid object" do
      input = schema.parse({ name: "Ada", address: "nope" })

      error = input.errors.find { |e| e.path == [:address] }
      expect(error.code).to eq(:invalid_object)
      expect(error.input).to eq("nope")
    end

    it "aggregates errors across the parent and the nested object" do
      input = schema.parse({ address: {} })

      expect(input.errors.map(&:path)).to contain_exactly([:name], [:address, :city])
    end
  end

  describe "array fields" do
    let(:employee) do
      Class.new(Accord::Schema) do
        string :name, required: true
        currency :salary
      end
    end

    let(:schema) do
      emp = employee
      Class.new(Accord::Schema) do
        array :employees, emp
      end
    end

    it "exposes a list of parsed schema instances" do
      input = schema.parse({ employees: [{ name: "Ada" }, { name: "Alan" }] })

      expect(input).to be_valid
      expect(input.employees.map(&:name)).to eq(%w[Ada Alan])
    end

    it "carries the element index in nested error paths" do
      input = schema.parse(
        { employees: [{ name: "Ada" }, { name: "Alan" }, { name: "Grace", salary: "$abc" }] },
      )

      expect(input).not_to be_valid
      error = input.errors.first
      expect(error.path).to eq([:employees, 2, :salary])
      expect(error.code).to eq(:invalid_currency)
    end

    it "reports a non-array value as an invalid array" do
      input = schema.parse({ employees: { name: "Ada" } })

      error = input.errors.find { |e| e.path == [:employees] }
      expect(error.code).to eq(:invalid_array)
    end

    it "reports a non-hash element as an invalid object at its index" do
      input = schema.parse({ employees: ["nope"] })

      error = input.errors.find { |e| e.path == [:employees, 0] }
      expect(error.code).to eq(:invalid_object)
    end
  end

  describe "strict mode" do
    let(:schema) do
      addr = address
      Class.new(Accord::Schema) do
        object :address, addr
      end
    end

    it "raises on a nested required field" do
      expect { schema.parse({ address: { zip: "75001" } }, strict: true) }
        .to raise_error(Accord::MissingField)
    end

    it "raises on a non-hash object" do
      expect { schema.parse({ address: "nope" }, strict: true) }
        .to raise_error(Accord::CoercionError)
    end
  end
end
