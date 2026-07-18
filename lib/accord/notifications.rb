# frozen_string_literal: true

require "active_support"
require "active_support/notifications"

module Accord
  # Adapter that forwards Accord's permissive-parse events to
  # ActiveSupport::Notifications. Set as Accord.notifier by "accord/rails".
  #
  #   ActiveSupport::Notifications.subscribe(/accord\.parse/) do |name, *, payload|
  #     StatsD.increment(name, tags: { field: payload[:field] })
  #   end
  module Notifications
    module_function

    def instrument(event, **payload)
      ActiveSupport::Notifications.instrument(event, payload)
    end
  end
end
