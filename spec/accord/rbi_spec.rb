# frozen_string_literal: true

RSpec.describe "RBI projection" do
  describe "sorbet type mapping" do
    it "maps each type to its Sorbet type" do
      expect(Accord::Types::String.new.sorbet).to eq("String")
      expect(Accord::Types::UUID.new.sorbet).to eq("String")
      expect(Accord::Types::ISOCurrency.new.sorbet).to eq("String")
      expect(Accord::Types::Boolean.new.sorbet).to eq("T::Boolean")
      expect(Accord::Types::Date.new.sorbet).to eq("Date")
      expect(Accord::Types::Decimal.new.sorbet).to eq("BigDecimal")
      expect(Accord::Types::Currency.new.sorbet).to eq("BigDecimal")
      expect(Accord::Types::Duration.new.sorbet).to eq("BigDecimal")
    end
  end

  describe "field return types" do
    it "wraps optional fields in T.nilable, leaves required/defaulted bare" do
      stub_const("S", Class.new(Accord::Schema) do
        currency :salary
        string :name, required: true
        boolean :active, default: true
      end)

      expect(S.fields[:salary].sorbet_return).to eq("T.nilable(BigDecimal)")
      expect(S.fields[:name].sorbet_return).to eq("String")
      expect(S.fields[:active].sorbet_return).to eq("T::Boolean")
    end
  end

  describe "Schema.rbi" do
    it "generates a typed RBI class declaration" do
      stub_const("Address", Class.new(Accord::Schema) { string :city, required: true })
      stub_const("CreateEmployee", Class.new(Accord::Schema) do
        string :name, required: true
        boolean :active, default: true
        currency :salary
        object :address, Address
      end)

      expect(CreateEmployee.rbi).to eq(<<~RBI.strip)
        class CreateEmployee < Accord::Schema
          sig { returns(String) }
          def name; end

          sig { returns(T::Boolean) }
          def active; end

          sig { returns(T.nilable(BigDecimal)) }
          def salary; end

          sig { returns(T.nilable(Address)) }
          def address; end
        end
      RBI
    end

    it "types arrays and money" do
      stub_const("Employee", Class.new(Accord::Schema) { string :name, required: true })
      stub_const("Payroll", Class.new(Accord::Schema) do
        array :employees, Employee
        money :salary
      end)

      expect(Payroll.rbi).to include("sig { returns(T.nilable(T::Array[Employee])) }")
      expect(Payroll.rbi).to include("sig { returns(T.nilable(Money)) }")
    end

    it "raises for an anonymous schema without a class_name" do
      expect { Class.new(Accord::Schema).rbi }.to raise_error(ArgumentError)
    end
  end
end
