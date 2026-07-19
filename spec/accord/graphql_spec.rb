# frozen_string_literal: true

RSpec.describe "GraphQL projection" do
  describe "scalar type mapping" do
    it "maps each type to its GraphQL scalar" do
      expect(Accord::Types::String.new.graphql).to eq("String")
      expect(Accord::Types::UUID.new.graphql).to eq("String")
      expect(Accord::Types::Email.new.graphql).to eq("String")
      expect(Accord::Types::Boolean.new.graphql).to eq("Boolean")
      expect(Accord::Types::Integer.new.graphql).to eq("Int")
      expect(Accord::Types::Decimal.new.graphql).to eq("String")
      expect(Accord::Types::Currency.new.graphql).to eq("String")
      expect(Accord::Types::Date.new.graphql).to eq("ISO8601Date")
      expect(Accord::Types::DateTime.new.graphql).to eq("ISO8601DateTime")
    end
  end

  describe "Schema.graphql" do
    it "generates an input type with non-null required fields" do
      stub_const("Address", Class.new(Accord::Schema) { string :city, required: true })
      stub_const("CreateEmployee", Class.new(Accord::Schema) do
        string :name, required: true
        boolean :active, default: true
        currency :salary
        date :hired_on
        object :address, Address, :required
      end)

      expect(CreateEmployee.graphql).to eq(<<~GQL.strip)
        input CreateEmployeeInput {
          name: String!
          active: Boolean
          salary: String
          hired_on: ISO8601Date
          address: AddressInput!
        }
      GQL
    end

    it "references a list of nested input types" do
      stub_const("Employee", Class.new(Accord::Schema) { string :name, required: true })
      stub_const("Payroll", Class.new(Accord::Schema) { array :employees, Employee, :required })

      expect(Payroll.graphql).to include("employees: [EmployeeInput!]!")
    end

    it "references MoneyInput for money fields" do
      stub_const("Comp", Class.new(Accord::Schema) { money :salary, required: true })

      expect(Comp.graphql).to include("salary: MoneyInput!")
    end

    it "accepts an explicit type_name for anonymous schemas" do
      schema = Class.new(Accord::Schema) { string :x, required: true }
      expect(schema.graphql(type_name: "FooInput")).to include("input FooInput {")
    end

    it "raises for an anonymous schema without a type_name" do
      expect { Class.new(Accord::Schema).graphql }.to raise_error(ArgumentError)
    end
  end

  describe "Schema.graphql_schemas" do
    it "collects the schema plus every nested input type" do
      stub_const("Address", Class.new(Accord::Schema) { string :city, required: true })
      stub_const("Employee", Class.new(Accord::Schema) { string :name, required: true })
      stub_const("Order", Class.new(Accord::Schema) do
        object :address, Address
        array :employees, Employee
        money :total
      end)

      schemas = Order.graphql_schemas

      expect(schemas.keys).to contain_exactly("Order", "Address", "Employee", "MoneyInput")
      expect(schemas["Address"]).to include("input AddressInput {")
      expect(schemas["MoneyInput"]).to eq(Accord::MoneyField::GRAPHQL_INPUT)
    end
  end
end
