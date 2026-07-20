# frozen_string_literal: true

describe Accord::Schema::List do
  let(:element) do
    stub_const("Employee", Class.new(Accord::Schema) { string :name, :required })
    Employee
  end

  subject(:list) { described_class.new(element) }

  describe "parsing" do
    it "parses each element, returning the instances" do
      result = list.parse!([{ name: "Ada" }, { name: "Bo" }])

      expect(result.map(&:name)).to eq(%w[Ada Bo])
      expect(result.size).to eq(2)
    end

    it "aggregates errors with each element's index in the path" do
      result = list.parse([{ name: "Ada" }, {}])

      expect(result).not_to be_valid
      expect(result.errors.map(&:path)).to eq([[1, :name]])
    end

    it "treats nil as an empty list" do
      expect(list.parse(nil)).to be_valid
    end

    it "reports a non-array source as an error rather than raising" do
      result = list.parse("nope")

      expect(result.errors.map(&:code)).to eq([:invalid_array])
    end

    it "raises InvalidInput from parse! when any element is invalid" do
      expect { list.parse!([{}]) }.to raise_error(Accord::InvalidInput)
    end
  end

  describe "projections (array-shaped, referencing the element)" do
    it "projects OpenAPI as an array of the element" do
      expect(list.openapi).to eq(type: "array", items: { "$ref" => "#/components/schemas/Employee" })
    end

    it "projects RBS and Sorbet array types" do
      expect(list.rbs).to eq("Array[Employee]")
      expect(list.sorbet).to eq("T::Array[Employee]")
    end

    it "projects a non-null GraphQL list of the element input" do
      expect(list.graphql).to eq("[EmployeeInput!]!")
    end

    it "collects the element's component and input-type schemas" do
      expect(list.openapi_schemas).to have_key("Employee")
      expect(list.graphql_schemas).to have_key("Employee")
    end
  end
end
