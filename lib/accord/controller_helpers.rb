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
  # whichever it needs. `from:` scopes the source (defaults to `params`) — a
  # Symbol names a params key, a proc handles anything else:
  #
  #     accord :filters, EmployeeFilters, from: :q
  #     accord :employee, CreateEmployee, from: -> { params.dig(:data, :attributes) }
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
      # named class when you want reuse or isolated tests. The inline schema is
      # named as a controller constant (`:employee` -> `EmployeeInput`) so it
      # still projects to OpenAPI/RBS/RBI/GraphQL; pass `const:` to choose that
      # name explicitly:
      #
      #   accord :employee, const: :NewHire do ... end   # -> NewHire constant
      # A one-element array denotes a **list** input — `accord :batch,
      # [CreateEmployee]` parses an array, and the reader returns an array of
      # parsed instances (errors carry each element's index: `[2, :salary]`).
      def accord(name, schema = nil, from: nil, const: nil, &block)
        if block
          raise ArgumentError, "accord :#{name} takes a schema or a block, not both" if schema

          schema = define_inline_schema(name, const, &block)
        elsif schema.nil?
          raise ArgumentError, "accord :#{name} requires a schema class or a block"
        elsif const
          raise ArgumentError, "accord :#{name}: `const:` only applies to an inline (block) schema"
        elsif schema.is_a?(Array) && schema.size != 1
          raise ArgumentError, "accord :#{name}: a list source takes exactly one schema, e.g. [CreateEmployee]"
        end

        define_method(name) { accord_input(name, schema, from) }
      end

      private

      # Build an anonymous schema from a block and name it as a controller
      # constant so it projects like a top-level schema class. The default name
      # (`:employee` -> `EmployeeInput`) carries an `Input` suffix to avoid
      # shadowing a same-named model. Refuses to clobber an existing constant
      # that isn't itself an Accord schema — pass `const:` to pick another name.
      def define_inline_schema(name, const, &block)
        const = (const || "#{name.to_s.split(/[^a-zA-Z0-9]+/).map(&:capitalize).join}Input").to_s

        if const_defined?(const, false)
          existing = const_get(const)
          unless existing.is_a?(Class) && existing < Schema
            raise ArgumentError,
                  "accord :#{name} would overwrite the existing constant #{const} — pass `const:` to choose another name"
          end
          remove_const(const)
        end

        const_set(const, Class.new(Schema, &block))
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

      source = accord_source(from)
      @accord_inputs[name] = schema.is_a?(Array) ? parse_accord_list(schema.first, source) : schema.parse!(source)
    end

    # Aggregates errors from a failed list parse for InvalidInput to render.
    ListErrors = Struct.new(:errors)

    # Parse a list input ([Schema] shorthand): each element through `element` at
    # its index, so errors read `[i, :field]` with no wrapper key. Returns the
    # parsed instances, or raises InvalidInput carrying every element's errors.
    def parse_accord_list(element, source)
      items = source.nil? ? [] : source
      unless items.is_a?(Array)
        raise Accord::InvalidInput, ListErrors.new([Accord::Error.new(path: [], code: :invalid_array, input: source)])
      end

      members = items.map.with_index { |item, index| element.parse(item, path: [index]) }
      errors = members.flat_map(&:errors)
      raise Accord::InvalidInput, ListErrors.new(errors) unless errors.empty?

      members
    end

    # Resolve the raw input for a declared schema. `from:` is a params key
    # (Symbol) for the common nested case, or a proc (evaluated in controller
    # context) for anything a single key can't express; nil reads `params`.
    def accord_source(from)
      case from
      when nil    then params
      when Symbol then params[from]
      else instance_exec(&from)
      end
    end
  end
end
