# frozen_string_literal: true

require_relative "../accord"
require_relative "controller_helpers"
require_relative "notifications"
require_relative "i18n"

module Accord
  # Opt-in Rails integration. `require "accord/rails"` (e.g. from a Gemfile with
  # `gem "accord", require: "accord/rails"`) wires permissive-parse events to
  # ActiveSupport::Notifications and, under Rails, makes ControllerHelpers
  # available to controllers.
  Accord.notifier = Accord::Notifications

  if defined?(Rails::Railtie)
    class Railtie < Rails::Railtie
      initializer "accord.controller_helpers" do
        ActiveSupport.on_load(:action_controller) do
          include Accord::ControllerHelpers
        end
      end

      rake_tasks do
        load File.expand_path("tasks/accord.rake", __dir__)
      end
    end
  end
end
