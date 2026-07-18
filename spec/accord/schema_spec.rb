# frozen_string_literal: true

require "bigdecimal"

RSpec.describe Accord::Schema do
  let(:schema) do
    Class.new(described_class) do
      string :name, required: true
      boolean :active, default: true
      currency :salary

      validate(:salary) { |salary| error(:must_be_positive) if salary.negative? }
    end
  end

  describe "parsing" do
    it "exposes coerced values directly, with no wrappers" do
      input = schema.parse({ name: "Ada", active: "yes", salary: "$1,000.00" })

      expect(input).to be_valid
      expect(input.name).to eq("Ada")
      expect(input.active).to be(true)
      expect(input.salary).to eq(BigDecimal("1000.00"))
    end

    it "accepts string keys" do
      input = schema.parse({ "name" => "Ada" })
      expect(input.name).to eq("Ada")
    end

    it "applies defaults for absent fields" do
      input = schema.parse({ name: "Ada" })
      expect(input.active).to be(true)
    end

    it "leaves optional absent fields nil" do
      input = schema.parse({ name: "Ada" })
      expect(input.salary).to be_nil
    end

    it "tolerates nil input" do
      expect(schema.parse(nil)).not_to be_valid
    end
  end

  describe "error aggregation" do
    it "collects every problem instead of failing fast" do
      input = schema.parse({ salary: "$abc" })

      expect(input).not_to be_valid
      codes = input.errors.map(&:code)
      expect(codes).to contain_exactly(:required, :invalid_currency)
    end

    it "records the offending input and path on each error" do
      input = schema.parse({ name: "Ada", salary: "$abc" })
      error = input.errors.first

      expect(error.field).to eq(:salary)
      expect(error.path).to eq([:salary])
      expect(error.code).to eq(:invalid_currency)
      expect(error.input).to eq("$abc")
    end

    it "reports a required field that is missing" do
      input = schema.parse({})
      required_error = input.errors.find { |e| e.field == :name }
      expect(required_error.code).to eq(:required)
    end
  end

  describe "validation" do
    it "runs custom validations against coerced values" do
      input = schema.parse({ name: "Ada", salary: "-5" })

      expect(input).not_to be_valid
      expect(input.errors.map(&:code)).to include(:must_be_positive)
    end

    it "skips field-scoped validations when the field failed coercion" do
      input = schema.parse({ name: "Ada", salary: "$abc" })

      expect(input.errors.map(&:code)).to contain_exactly(:invalid_currency)
    end

    it "skips field-scoped validations when the field is absent" do
      input = schema.parse({ name: "Ada" })
      expect(input).to be_valid
    end

    it "runs validations in declaration order" do
      order = []
      klass = Class.new(described_class) do
        string :a
        string :b
        validate(:a) { order << :a }
        validate(:b) { order << :b }
      end

      klass.parse({ a: "x", b: "y" })
      expect(order).to eq(%i[a b])
    end
  end

  describe "strict mode" do
    it "raises on the first coercion failure" do
      expect { schema.parse({ name: "Ada", salary: "$abc" }, strict: true) }
        .to raise_error(Accord::CoercionError)
    end

    it "raises on a missing required field" do
      expect { schema.parse({}, strict: true) }
        .to raise_error(Accord::MissingField)
    end

    it "does not apply permissive coercion" do
      expect { schema.parse({ name: "Ada", active: "yes" }, strict: true) }
        .to raise_error(Accord::CoercionError)
    end
  end

  describe "parse!" do
    it "returns the typed input when valid" do
      expect(schema.parse!({ name: "Ada" }).name).to eq("Ada")
    end

    it "raises InvalidInput carrying the errors when invalid" do
      expect { schema.parse!({}) }.to raise_error(Accord::InvalidInput) do |error|
        expect(error.errors.map(&:code)).to include(:required)
      end
    end
  end

  describe "inheritance" do
    it "extends a parent schema without mutating it" do
      child = Class.new(schema) { string :department }

      expect(child.fields.keys).to include(:name, :department)
      expect(schema.fields.keys).not_to include(:department)
    end
  end
end
