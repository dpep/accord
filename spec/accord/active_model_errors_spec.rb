# frozen_string_literal: true

require "accord/active_model_errors"

describe Accord::ActiveModelErrors do
  let(:schema) do
    Class.new(Accord::Schema) do
      string   :name, :required
      email    :email, :required
      currency :salary, :positive
    end
  end

  it "builds an ActiveModel::Errors from a parsed schema" do
    errors = schema.parse({ email: "nope", salary: "-5" }).active_model_errors

    expect(errors).to be_a(ActiveModel::Errors)
    expect(errors.attribute_names).to contain_exactly(:name, :email, :salary)
  end

  it "carries the Accord code as the ActiveModel error type (details stay machine-readable)" do
    errors = schema.parse({ name: "Ada", email: "nope", salary: "10" }).active_model_errors

    expect(errors.details[:email]).to eq([{ error: :invalid_email }])
  end

  it "carries validator metadata into details" do
    bounded = Class.new(Accord::Schema) { integer :age, min: 18 }
    errors = bounded.parse({ age: 5 }).active_model_errors

    expect(errors.details[:age].first).to include(error: :too_small, expected: 18)
  end

  it "renders messages via Accord's localized catalog" do
    input = schema.parse({ email: "a@b.co", salary: "-5" })   # name required, salary not positive
    errors = input.active_model_errors
    name_error = input.errors.find { |e| e.field == :name }

    expect(errors[:name]).to eq([Accord::Messages.message(name_error)])
    expect(errors.full_messages).to include(a_string_starting_with("Name"))
  end

  it "flattens a nested path into a form-style attribute key" do
    child = Class.new(Accord::Schema) { string :city, :required }
    parent = Class.new(Accord::Schema) { array :addresses, child }

    errors = parent.parse({ addresses: [{}, { city: "Paris" }] }).active_model_errors

    expect(errors.attribute_names).to include(:"addresses[0].city")
  end

  it "uses :base for a root-level error" do
    root_error = Struct.new(:errors).new([Accord::Error.new(path: [], code: :invalid_object)])

    expect(described_class.build(root_error).attribute_names).to eq([:base])
  end
end
