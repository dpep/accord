# frozen_string_literal: true

RSpec.describe "permissive-parse instrumentation" do
  recorder = Struct.new(:events) do
    def instrument(event, **payload)
      events << { event:, payload: }
    end
  end

  let(:events) { [] }

  let(:schema) do
    Class.new(Accord::Schema) do
      string :name, required: true
      currency :salary do
        validate(:must_be_positive) { |salary| error(:must_be_positive) if salary.negative? }
      end
    end
  end

  around do |example|
    previous = Accord.notifier
    Accord.notifier = recorder.new(events)
    example.run
    Accord.notifier = previous
  end

  it "emits an event per tolerated coercion error" do
    schema.parse({ salary: "$abc" })

    event = events.find { |e| e[:event] == "accord.parse.invalid_currency" }
    expect(event[:payload]).to include(field: :salary, input: "$abc")
  end

  it "emits an event for a missing required field" do
    schema.parse({})

    events_names = events.map { |e| e[:event] }
    expect(events_names).to include("accord.parse.required")
  end

  it "emits an event for a validation failure" do
    schema.parse({ name: "Ada", salary: "-5" })

    expect(events.map { |e| e[:event] }).to include("accord.parse.must_be_positive")
  end

  it "stays silent in strict mode" do
    expect { schema.parse({ name: "Ada", salary: "$abc" }, strict: true) }
      .to raise_error(Accord::CoercionError)
    expect(events).to be_empty
  end

  it "does not emit for valid input" do
    schema.parse({ name: "Ada", salary: "10" })
    expect(events).to be_empty
  end
end
