# frozen_string_literal: true

require "tapioca"
require "tapioca/dsl"
require "tapioca/dsl/compilers/accord_schema"

# Drives the Tapioca DSL compiler's #decorate directly and prints the RBI,
# exercising the real generation logic without shelling out to the sorbet binary.
describe Tapioca::Dsl::Compilers::AccordSchema do
  def rbi_for(constant)
    file = RBI::File.new(strictness: "strong")
    pipeline = Tapioca::Dsl::Pipeline.new(requested_constants: [], requested_compilers: [described_class])
    described_class.new(pipeline, file.root, constant, {}).decorate
    Tapioca::DEFAULT_RBI_FORMATTER.print_file(file)
  end

  it "gathers Accord::Schema subclasses" do
    stub_const("Widget", Class.new(Accord::Schema) { string :name, required: true })
    expect(described_class.gather_constants).to include(Widget)
  end

  it "generates typed reader RBI for a schema" do
    stub_const("Address", Class.new(Accord::Schema) { string :city, required: true })
    stub_const("CreateEmployee", Class.new(Accord::Schema) do
      string :name, required: true
      boolean :active, default: true
      currency :salary
      object :address, Address
    end)

    rbi = rbi_for(CreateEmployee)

    expect(rbi).to include("class CreateEmployee")
    expect(rbi).to include("sig { returns(String) }")
    expect(rbi).to include("def name; end")
    expect(rbi).to include("sig { returns(T::Boolean) }")
    expect(rbi).to include("sig { returns(T.nilable(BigDecimal)) }")
    expect(rbi).to include("def salary; end")
    expect(rbi).to include("sig { returns(T.nilable(Address)) }")
  end

  it "types the parse entry points as the schema class" do
    stub_const("CreateEmployee", Class.new(Accord::Schema) { string :name, required: true })

    rbi = rbi_for(CreateEmployee)

    expect(rbi).to include("class << self")
    expect(rbi).to include("def parse(input, strict:")
    expect(rbi).to include("def parse!(input, strict:")
    expect(rbi).to include("returns(T.attached_class)")
  end
end
