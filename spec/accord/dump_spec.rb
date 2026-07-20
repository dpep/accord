# frozen_string_literal: true

describe "Schema#dump" do
  it "emits canonical external values — the inverse of parse" do
    stub_const("Address", Class.new(Accord::Schema) { string :city })
    schema = Class.new(Accord::Schema) do
      string   :name
      currency :salary
      date     :hired_on
      uuid     :id
      boolean  :active
      object   :address, Address
    end

    input = schema.parse({
      name: "Ada",
      salary: "$1,000.00",
      hired_on: "2026-01-15",
      id: "550E8400-E29B-41D4-A716-446655440000",
      active: "yes",
      address: { city: "Paris" },
    })

    expect(input.dump).to eq(
      name: "Ada",
      salary: "1000.00",
      hired_on: "2026-01-15",
      id: "550e8400-e29b-41d4-a716-446655440000",
      active: true,
      address: { city: "Paris" },
    )
  end

  it "dumps arrays of nested schemas" do
    stub_const("Item", Class.new(Accord::Schema) { currency :price })
    schema = Class.new(Accord::Schema) { array :items, Item }

    input = schema.parse({ items: [{ price: "10.00" }, { price: "$20" }] })
    expect(input.dump).to eq(items: [{ price: "10.00" }, { price: "20.00" }])
  end

  it "dumps absent optional fields as nil" do
    schema = Class.new(Accord::Schema) { currency :salary }
    expect(schema.parse({}).dump).to eq(salary: nil)
  end
end
