# frozen_string_literal: true

require "bigdecimal"

describe "coercion observability (permissive -> strict)" do
  recorder = Struct.new(:events) do
    def instrument(event, **payload)
      events << { event:, payload: }
    end
  end

  let(:events) { [] }

  let(:schema) do
    Class.new(Accord::Schema) do
      boolean  :active
      currency :salary
      integer  :count
    end
  end

  def coerced_events
    events.select { |e| e[:event] == "accord.parse.coerced" }
  end

  around do |example|
    previous_notifier = Accord.notifier
    previous_observe = Accord.config.observe_coercions
    Accord.notifier = recorder.new(events)
    Accord.config.observe_coercions = true
    example.run
    Accord.notifier = previous_notifier
    Accord.config.observe_coercions = previous_observe
  end

  it "emits accord.parse.coerced only for input strict would reject" do
    schema.parse({ active: "yes", salary: "$1,000.00", count: 42 })

    # "yes" and "$1,000.00" are permissive-only; 42 is strict-clean
    expect(coerced_events.map { |e| e[:payload][:field] }).to contain_exactly(:active, :salary)
  end

  it "carries the raw input variant and the canonical value" do
    schema.parse({ salary: "$1,000.00" })

    event = coerced_events.first
    expect(event[:payload]).to include(field: :salary, path: [:salary], input: "$1,000.00", type: :currency)
    expect(event[:payload][:value]).to eq(BigDecimal("1000"))
  end

  it "stays silent when observe_coercions is off" do
    Accord.config.observe_coercions = false

    schema.parse({ active: "yes", salary: "$1,000.00" })
    expect(coerced_events).to be_empty
  end

  it "does not fire in strict mode" do
    expect { schema.parse({ active: "yes" }, strict: true) }.to raise_error(Accord::CoercionError)
    expect(coerced_events).to be_empty
  end
end
