# frozen_string_literal: true

require "accord/notifications"

describe Accord::Notifications do
  let(:schema) do
    Class.new(Accord::Schema) do
      currency :salary
    end
  end

  around do |example|
    previous = Accord.notifier
    Accord.notifier = described_class
    example.run
    Accord.notifier = previous
  end

  it "forwards permissive-parse events to ActiveSupport::Notifications" do
    received = []
    subscription = ActiveSupport::Notifications.subscribe("accord.parse.invalid_currency") do |name, _start, _finish, _id, payload|
      received << [name, payload]
    end

    schema.parse({ salary: "$abc" })

    name, payload = received.first
    expect(name).to eq("accord.parse.invalid_currency")
    expect(payload).to include(field: :salary, input: "$abc")
  ensure
    ActiveSupport::Notifications.unsubscribe(subscription)
  end
end
