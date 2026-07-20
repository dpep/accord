# frozen_string_literal: true

require "accord/rspec"

describe "Accord RSpec matchers" do
  let(:schema) do
    Class.new(Accord::Schema) do
      string :name, :required
      integer :age do
        between 18..120
      end
    end
  end

  describe "conform_to" do
    it "passes when the value satisfies the schema" do
      expect({ name: "Ada", age: "30" }).to conform_to(schema)
    end

    it "fails when it doesn't (and reports why)" do
      expect({ age: "5" }).not_to conform_to(schema)
      expect { expect({}).to conform_to(schema) }
        .to raise_error(RSpec::Expectations::ExpectationNotMetError, /name: required/)
    end
  end

  describe "have_error" do
    subject(:result) { schema.parse({ age: "5" }) }

    it "matches by code" do
      expect(result).to have_error(:required)
    end

    it "narrows by path (varargs) and metadata" do
      expect(result).to have_error(:required).at(:name)
      expect(result).to have_error(:out_of_range).at(:age).with(min: 18, max: 120)
    end

    it "does not match the wrong path" do
      expect(result).not_to have_error(:required).at(:age)
    end
  end
end
