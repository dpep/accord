# frozen_string_literal: true

RSpec.describe "RBS projection" do
  describe "scalar type mapping" do
    it "maps each type to its RBS type" do
      expect(Accord::Types::String.new.rbs).to eq("String")
      expect(Accord::Types::UUID.new.rbs).to eq("String")
      expect(Accord::Types::ISOCurrency.new.rbs).to eq("String")
      expect(Accord::Types::Boolean.new.rbs).to eq("bool")
      expect(Accord::Types::Date.new.rbs).to eq("Date")
      expect(Accord::Types::Decimal.new.rbs).to eq("BigDecimal")
      expect(Accord::Types::Currency.new.rbs).to eq("BigDecimal")
      expect(Accord::Types::Duration.new.rbs).to eq("BigDecimal")
    end
  end

  describe "Schema.rbs" do
    it "generates a typed class declaration" do
      stub_const("Address", Class.new(Accord::Schema) { string :city, required: true })
      stub_const("CreateEmployee", Class.new(Accord::Schema) do
        string :name, required: true
        boolean :active, default: true
        currency :salary
        date :hired_on
        uuid :id, required: true
        object :address, Address
      end)

      expect(CreateEmployee.rbs).to eq(<<~RBS.strip)
        class CreateEmployee < Accord::Schema
          def name: () -> String
          def active: () -> bool
          def salary: () -> BigDecimal?
          def hired_on: () -> Date?
          def id: () -> String
          def address: () -> Address?
        end
      RBS
    end

    it "types arrays and money" do
      stub_const("Employee", Class.new(Accord::Schema) { string :name, required: true })
      stub_const("Payroll", Class.new(Accord::Schema) do
        array :employees, Employee
        money :salary
      end)

      expect(Payroll.rbs).to include("def employees: () -> Array[Employee]?")
      expect(Payroll.rbs).to include("def salary: () -> Money?")
    end

    it "makes required and defaulted fields non-nilable, optional ones nilable" do
      stub_const("Flags", Class.new(Accord::Schema) do
        string :required_field, required: true
        string :defaulted_field, default: "x"
        string :optional_field
      end)

      rbs = Flags.rbs
      expect(rbs).to include("def required_field: () -> String")
      expect(rbs).to include("def defaulted_field: () -> String")
      expect(rbs).to include("def optional_field: () -> String?")
    end

    it "accepts an explicit class_name for anonymous schemas" do
      schema = Class.new(Accord::Schema) { string :x, required: true }
      expect(schema.rbs(class_name: "Foo")).to include("class Foo < Accord::Schema")
    end

    it "raises for an anonymous schema without a class_name" do
      expect { Class.new(Accord::Schema).rbs }.to raise_error(ArgumentError)
    end
  end
end
