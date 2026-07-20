# frozen_string_literal: true

describe "configuration" do
  let(:schema) do
    Class.new(Accord::Schema) do
      currency :salary
    end
  end

  around do |example|
    previous = Accord.config.strict
    example.run
    Accord.config.strict = previous
  end

  it "defaults the parse mode to non-strict" do
    expect(schema.parse({ salary: "$abc" })).not_to be_valid
  end

  it "honors a configured default of strict" do
    Accord.configure { |c| c.strict = true }

    expect { schema.parse({ salary: "$abc" }) }.to raise_error(Accord::CoercionError)
  end

  it "lets a per-call strict override win over the config" do
    Accord.configure { |c| c.strict = true }

    expect(schema.parse({ salary: "$abc" }, strict: false)).not_to be_valid
  end
end
