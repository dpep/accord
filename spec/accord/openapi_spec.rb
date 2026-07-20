# frozen_string_literal: true

describe "OpenAPI projection" do
  describe "Schema.openapi" do
    it "builds an object schema with properties, required, and validator constraints" do
      stub_const("CreateEmployee", Class.new(Accord::Schema) do
        string  :name, :required
        integer :age do
          between 18..120
        end
        boolean :active, default: true
      end)

      expect(CreateEmployee.openapi).to eq(
        type: "object",
        properties: {
          name: { type: "string" },
          age: { type: "integer", minimum: 18, maximum: 120 },
          active: { type: "boolean" },
        },
        required: %i[name],
      )
    end

    it "omits required when no field is required" do
      stub_const("Filters", Class.new(Accord::Schema) { string :q })
      expect(Filters.openapi).to eq(type: "object", properties: { q: { type: "string" } })
    end

    it "references named nested schemas by \$ref" do
      stub_const("Address", Class.new(Accord::Schema) { string :city, :required })
      stub_const("Employee", Class.new(Accord::Schema) do
        object :address, Address
        array  :prior_addresses, Address
      end)

      props = Employee.openapi[:properties]
      expect(props[:address]).to eq("$ref" => "#/components/schemas/Address")
      expect(props[:prior_addresses]).to eq(
        type: "array", items: { "$ref" => "#/components/schemas/Address" },
      )
    end
  end

  describe "Schema.openapi_schemas" do
    it "collects the schema and its nested schemas, keyed by class name" do
      stub_const("Address", Class.new(Accord::Schema) { string :city, :required })
      stub_const("Employee", Class.new(Accord::Schema) do
        string :name, :required
        object :address, Address
      end)

      schemas = Employee.openapi_schemas
      expect(schemas.keys).to contain_exactly("Employee", "Address")
      expect(schemas["Address"]).to eq(
        type: "object", properties: { city: { type: "string" } }, required: %i[city],
      )
    end
  end

  describe "Schema.openapi_ref" do
    it "returns a $ref pointer to the schema's component" do
      stub_const("Employee", Class.new(Accord::Schema) { string :name, :required })
      expect(Employee.openapi_ref).to eq("$ref" => "#/components/schemas/Employee")
    end

    it "raises for an anonymous schema" do
      expect { Class.new(Accord::Schema).openapi_ref }.to raise_error(ArgumentError)
    end
  end
end
