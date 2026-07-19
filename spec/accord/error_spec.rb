# frozen_string_literal: true

RSpec.describe Accord::Error do
  it "exposes its structured attributes" do
    error = described_class.new(
      path: [:discount], code: :too_small, validator: :min, value: -5, expected: 0,
    )

    expect(error.path).to eq([:discount])
    expect(error.code).to eq(:too_small)
    expect(error.validator).to eq(:min)
    expect(error.value).to eq(-5)
    expect(error.metadata).to eq(expected: 0)
  end

  it "defaults field to the last path segment" do
    error = described_class.new(path: [:employees, 3, :salary], code: :not_positive)
    expect(error.field).to eq(:salary)
  end

  it "carries no message — rendering is a separate concern" do
    expect(described_class.new(path: [:x], code: :bad)).not_to respond_to(:message)
  end

  it "serializes to structured data, dropping nil keys" do
    error = described_class.new(
      path: [:discount], code: :too_small, validator: :min, value: -5, expected: 0,
    )

    expect(error.to_h).to eq(
      path: [:discount], field: :discount, code: :too_small, validator: :min, value: -5, expected: 0,
    )
  end

  it "serializes a minimal error to just path, field, and code" do
    expect(described_class.new(path: [:salary], code: :not_positive).to_h)
      .to eq(path: [:salary], field: :salary, code: :not_positive)
  end

  it "compares by value" do
    a = described_class.new(path: [:x], code: :bad, validator: :min, expected: 0)
    b = described_class.new(path: [:x], code: :bad, validator: :min, expected: 0)
    expect(a).to eq(b)
  end
end
