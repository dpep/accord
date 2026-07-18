# frozen_string_literal: true

require_relative "errors"

module Accord
  # Rails controller integration. Include in a controller to parse request
  # params through a schema; invalid input raises Accord::InvalidInput, which is
  # rendered as a 422 by the rescue_from installed on include.
  #
  #   class EmployeesController < ApplicationController
  #     include Accord::ControllerHelpers
  #
  #     def create
  #       input = parse_input(CreateEmployee)
  #       EmployeeService.call(input)
  #       head :created
  #     end
  #   end
  #
  # The schema is itself the allowlist — it reads only its declared fields and
  # ignores everything else — so params are taken unfiltered.
  module ControllerHelpers
    def self.included(base)
      return unless base.respond_to?(:rescue_from)

      base.rescue_from(Accord::InvalidInput) do |error|
        render json: { errors: error.errors.map(&:to_h) }, status: :unprocessable_entity
      end
    end

    # Parse params through a schema, returning the typed input. Raises
    # Accord::InvalidInput (→ 422) when the input does not satisfy the schema.
    def parse_input(schema, source = params)
      input = schema.parse(accord_param_hash(source))
      raise Accord::InvalidInput, input unless input.valid?

      input
    end

    private

    def accord_param_hash(source)
      source.respond_to?(:to_unsafe_h) ? source.to_unsafe_h : source
    end
  end
end
