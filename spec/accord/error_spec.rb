# frozen_string_literal: true

RSpec.describe Accord::Error do
  subject(:error) do
    described_class.new(
      field: :salary,
      path: [:employee, :salary],
      code: :invalid_currency,
      input: "$abc",
    )
  end

  it "exposes its structured attributes" do
    expect(error.field).to eq(:salary)
    expect(error.path).to eq([:employee, :salary])
    expect(error.code).to eq(:invalid_currency)
    expect(error.input).to eq("$abc")
  end

  it "defaults its message to the code" do
    expect(error.message).to eq("invalid_currency")
  end

  it "serializes to a hash for rendering" do
    expect(error.to_h).to eq(
      field: :salary,
      path: [:employee, :salary],
      code: :invalid_currency,
      message: "invalid_currency",
      input: "$abc",
      value: nil,
    )
  end

  it "compares by value" do
    twin = described_class.new(
      field: :salary,
      path: [:employee, :salary],
      code: :invalid_currency,
      input: "$abc",
    )
    expect(error).to eq(twin)
  end
end
