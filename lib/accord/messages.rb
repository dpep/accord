# frozen_string_literal: true

module Accord
  # Renders structured Accord::Error objects into localized strings via I18n —
  # the optional rendering layer that pairs with the message-free errors. The
  # helpers mirror ActiveModel::Errors (message / full_message / messages /
  # full_messages), so they drop into Rails error handling.
  #
  #   def render_accord_errors(error)
  #     render json: { errors: Accord::Messages.messages(error.errors) }, status: 422
  #   end
  #
  # Messages come from the shipped accord.errors.<code> locale; override any key
  # in your own config/locales. Requires the i18n gem (loaded by "accord/i18n").
  module Messages
    module_function

    # A field-less message for one error, e.g. "must be at least 18".
    def message(error)
      ::I18n.t("accord.errors.#{error.code}", **error.metadata, default: error.code.to_s)
    end

    # A full message with the humanized field prepended, e.g. "Age must be at
    # least 18".
    def full_message(error)
      "#{humanize(error.field)} #{message(error)}".strip
    end

    # Field-less messages grouped by field (like ActiveModel `errors.messages`):
    #   { salary: ["must be positive"], name: ["is required"] }
    def messages(errors)
      errors.group_by(&:field).transform_values { |errs| errs.map { |e| message(e) } }
    end

    # Full messages as a flat list (like ActiveModel `errors.full_messages`).
    def full_messages(errors)
      errors.map { |error| full_message(error) }
    end

    def humanize(field)
      field.to_s.tr("_", " ").capitalize
    end
  end
end
