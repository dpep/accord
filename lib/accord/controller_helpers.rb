# frozen_string_literal: true

require_relative "errors"
require_relative "schema"

module Accord
  # Rails controller integration. The schema is the entry point — call
  # `Schema.parse!(params)` directly, or declare an input with the `accord`
  # macro. Either way, invalid input raises Accord::InvalidInput, rendered as a
  # 422 by the rescue_from installed on include.
  #
  #   class EmployeesController < ApplicationController
  #     accord :employee, CreateEmployee
  #
  #     def create
  #       EmployeeService.call(employee)   # parsed + memoized; 422 if invalid
  #       head :created
  #     end
  #   end
  #
  # The macro declares a lazily-parsed, memoized reader rather than an action
  # hook, so a controller can declare several inputs and each action uses
  # whichever it needs. `from:` scopes the source (defaults to `params`):
  #
  #     accord :filters, EmployeeFilters, from: -> { params[:q] }
  #
  # The schema is itself the allowlist — it reads only its declared fields via
  # `[]`/`key?`, which ActionController::Parameters permits without `permit` —
  # so params are consumed directly, unfiltered.
  module ControllerHelpers
    def self.included(base)
      base.extend(ClassMethods)
      return unless base.respond_to?(:rescue_from)

      base.rescue_from(Accord::InvalidInput) { |error| render_accord_errors(error) }
    end

    module ClassMethods
      # Declare a memoized input reader backed by a schema. Pass a schema class,
      # or a block to define an anonymous schema inline:
      #
      #   accord :employee, CreateEmployee          # reuse a named schema
      #
      #   accord :employee do                       # inline, single-use
      #     string   :name, :required
      #     currency :salary, :positive
      #   end
      #
      # Inline schemas are convenient for a simple, one-off input; reach for a
      # named class when you want reuse, isolated tests, or an OpenAPI/RBS/
      # GraphQL projection (those require a named schema).
      def accord(name, schema = nil, from: nil, &block)
        if block
          raise ArgumentError, "accord :#{name} takes a schema or a block, not both" if schema

          schema = Class.new(Schema, &block)
        elsif schema.nil?
          raise ArgumentError, "accord :#{name} requires a schema class or a block"
        end

        define_method(name) { accord_input(name, schema, from) }
      end
    end

    private

    # Override in a controller to customize the 422 response.
    def render_accord_errors(error)
      render json: { errors: error.errors.map(&:to_h) }, status: :unprocessable_entity
    end

    def accord_input(name, schema, from)
      @accord_inputs ||= {}
      return @accord_inputs[name] if @accord_inputs.key?(name)

      source = from ? instance_exec(&from) : params
      @accord_inputs[name] = schema.parse!(source)
    end
  end
end
