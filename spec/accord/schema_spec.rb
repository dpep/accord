# frozen_string_literal: true

require "bigdecimal"

describe Accord::Schema do
  let(:schema) do
    Class.new(described_class) do
      string :name, required: true
      boolean :active, default: true
      currency :salary do
        validate(:must_be_positive) { |salary| error(:must_be_positive) if salary.negative? }
      end
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

    it "reports a single shape error for non-hash root input, not per-field required" do
      result = schema.parse("garbage")

      expect(result).not_to be_valid
      expect(result.errors.map(&:code)).to eq([:invalid_object])
      expect(result.errors.first.input).to eq("garbage")
    end

    it "raises on non-hash root input in strict mode" do
      expect { schema.parse([1, 2], strict: true) }.to raise_error(Accord::CoercionError)
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
    it "runs field validators against coerced values" do
      input = schema.parse({ name: "Ada", salary: "-5" })

      expect(input).not_to be_valid
      expect(input.errors.map(&:code)).to include(:must_be_positive)
    end

    it "skips validators when the field failed coercion" do
      input = schema.parse({ name: "Ada", salary: "$abc" })

      expect(input.errors.map(&:code)).to contain_exactly(:invalid_currency)
    end

    it "skips validators when the field is absent" do
      input = schema.parse({ name: "Ada" })
      expect(input).to be_valid
    end

    it "aggregates every error across fields in one pass" do
      klass = Class.new(described_class) do
        string :name, required: true
        integer :age do
          min 18
        end
      end

      input = klass.parse({ age: "5" })
      expect(input.errors.map(&:code)).to contain_exactly(:required, :too_small)
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

  describe "decimal fields" do
    let(:schema) do
      Class.new(described_class) do
        decimal :rate, scale: 4
      end
    end

    it "enforces the declared scale" do
      expect(schema.parse({ rate: "0.1234" }).rate).to eq(BigDecimal("0.1234"))
      expect(schema.parse({ rate: "0.12345" })).not_to be_valid
    end
  end

  describe "uuid fields" do
    let(:schema) do
      Class.new(described_class) do
        uuid :id
      end
    end

    it "canonicalizes to a lowercase UUID" do
      input = schema.parse({ id: "550E8400-E29B-41D4-A716-446655440000" })
      expect(input.id).to eq("550e8400-e29b-41d4-a716-446655440000")
    end
  end

  describe "duration fields" do
    let(:schema) do
      Class.new(described_class) do
        duration :work_time, unit: :hours
      end
    end

    it "parses a duration into a BigDecimal" do
      expect(schema.parse({ work_time: "1.5" }).work_time).to eq(BigDecimal("1.5"))
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

  describe "reading parsed values" do
    let(:input) { schema.parse({ name: "Ada", salary: "$1,000.00" }) }

    it "exposes the internal values as a hash via #to_h" do
      expect(input.to_h).to include(name: "Ada", active: true, salary: BigDecimal("1000.00"))
    end

    it "reads a single field via #[]" do
      expect(input[:name]).to eq("Ada")
    end

    it "recurses nested schemas and arrays into plain hashes" do
      stub_const("Addr", Class.new(described_class) { string :city, :required })
      stub_const("Team", Class.new(described_class) do
        object :lead_address, Addr
        array :member_addresses, Addr
      end)

      result = Team.parse({ lead_address: { city: "Paris" }, member_addresses: [{ city: "Rome" }] }).to_h

      expect(result[:lead_address]).to eq(city: "Paris")
      expect(result[:member_addresses]).to eq([{ city: "Rome" }])
    end
  end

  describe ".descendants" do
    it "collects schemas descending from a root, recursively" do
      stub_const("Parent", Class.new(described_class))
      stub_const("Child", Class.new(Parent))
      stub_const("Grandchild", Class.new(Child))

      expect(Parent.descendants).to contain_exactly(Child, Grandchild)
      expect(described_class.descendants).to include(Parent, Child, Grandchild)
    end
  end

  describe "defaults" do
    it "coerces a non-canonical default to the field's type" do
      klass = Class.new(described_class) do
        boolean :active, default: "yes"
        integer :count, default: "5"
      end

      input = klass.parse({})
      expect(input.active).to be(true)
      expect(input.count).to eq(5)
    end

    it "coerces a proc default when it runs" do
      klass = Class.new(described_class) { boolean :active, default: -> { "no" } }
      expect(klass.parse({}).active).to be(false)
    end

    it "rejects a default of the wrong type at declaration" do
      expect { Class.new(described_class) { boolean :flag, default: "nonsense" } }
        .to raise_error(ArgumentError, /default/)
    end

    it "rejects a default that violates the field's validators at declaration" do
      expect { Class.new(described_class) { integer :n, default: -5, min: 0 } }
        .to raise_error(ArgumentError, /default/)
    end
  end

  describe ".field" do
    it "declares a scalar field backed by an explicit type instance" do
      klass = Class.new(described_class) { field :code, Accord::Types::UUID.new, :required }

      expect(klass.parse({ code: "550E8400-E29B-41D4-A716-446655440000" }).code).to eq("550e8400-e29b-41d4-a716-446655440000")
      expect(klass.fields[:code].required?).to be(true)
    end
  end
end
