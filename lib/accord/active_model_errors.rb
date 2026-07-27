# frozen_string_literal: true

require "active_model"
require_relative "../accord"
require_relative "messages"
require_relative "i18n"

module Accord
  # Adapts Accord's structured errors into an ActiveModel::Errors object, so an
  # existing Rails app's form helpers, error partials, and `full_messages`
  # consume Accord errors unchanged. Opt-in Rails interop — needs ActiveModel;
  # loaded by "accord/rails".
  #
  #   errors = Accord::ActiveModelErrors.build(input)   # input = a parsed schema
  #   errors[:email]           # => ["is invalid"]              (localized Accord message)
  #   errors.full_messages     # => ["Email is invalid", ...]
  #   errors.details[:email]   # => [{ error: :invalid_email }] (machine-readable Accord code)
  #
  # Each Accord::Error becomes an ActiveModel error whose `type` is the Accord
  # code (so `details` stays machine-readable), carrying the localized Accord
  # message and the validator metadata as options.
  module ActiveModelErrors
    module_function

    # An ActiveModel::Errors populated from a parsed Accord schema instance (or
    # anything whose #errors returns Accord::Error). Each error keeps its Accord
    # `code` as the ActiveModel error type (so `details` stays machine-readable),
    # carries the localized Accord message, and folds validator metadata into the
    # options (so it appears in `details` too).
    def build(input, base: Base.new(input))
      errors = ::ActiveModel::Errors.new(base)
      input.errors.each do |error|
        errors.add(attribute_for(error), error.code, message: Messages.message(error), **error.metadata)
      end
      errors
    end

    # A minimal ActiveModel base so ActiveModel::Errors can humanize attributes
    # and build full messages. Reads attribute values from the parsed input for
    # message interpolation; unknown (e.g. flattened nested) keys read as nil.
    class Base
      include ::ActiveModel::Model

      def initialize(input) = @input = input

      def read_attribute_for_validation(name)
        @input[name] if @input.respond_to?(:[])
      end
    end

    # Map an Accord error's path to an ActiveModel attribute: a top-level field is
    # its own symbol (`:email`); a nested path flattens to a form-style key
    # (`[:employees, 2, :salary]` -> `:"employees[2].salary"`); a root-level error
    # is `:base` (the ActiveModel convention).
    def attribute_for(error)
      path = error.path
      return :base if path.empty?
      return path.first.to_sym if path.size == 1

      key = +""
      path.each do |segment|
        if segment.is_a?(::Integer)
          key << "[#{segment}]"
        else
          key << "." unless key.empty?
          key << segment.to_s
        end
      end
      key.to_sym
    end
  end

  class Schema
    # An ActiveModel::Errors view of this parsed input's errors — for Rails form
    # helpers, error partials, and full_messages. Requires "accord/rails" (or
    # "accord/active_model_errors").
    def active_model_errors
      ActiveModelErrors.build(self)
    end
  end
end
