# frozen_string_literal: true

require_relative "errors"
require_relative "schema"
require_relative "list_schema"

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
      #
      # A one-element array denotes a **list** input — `accord :batch,
      # [CreateEmployee]` parses an array (the reader returns the parsed
      # elements, errors carrying each index: `[2, :salary]`) and mints a
      # projectable ListSchema constant, just like an inline block.
      def accord(name, schema = nil, from: nil, const: nil, &block)
        input =
          if block
            raise ArgumentError, "accord :#{name} takes a schema or a block, not both" if schema

            register_accord_schema(name, const) { Class.new(Schema, &block) }
          elsif schema.nil?
            raise ArgumentError, "accord :#{name} requires a schema class or a block"
          elsif schema.is_a?(Array)
            raise ArgumentError, "accord :#{name}: a list source takes exactly one schema, e.g. [CreateEmployee]" if schema.size != 1

            register_accord_schema(name, const) { ListSchema.new(schema.first) }
          elsif const
            raise ArgumentError, "accord :#{name}: `const:` only applies to an inline (block) or list schema"
          else
            schema
          end

        accord_inputs[name] = input
        define_method(name) { accord_input(name, input, from) }
      end

      # The inputs declared on this controller, as `{ reader_name => schema }`
      # (a schema class, or an Accord::ListSchema for a `[Schema]` list). Fully
      # introspectable — and the source the Tapioca controller compiler types the
      # generated readers from. A subclass inherits its parents' declarations.
      def accord_inputs
        @accord_inputs ||= superclass.respond_to?(:accord_inputs) ? superclass.accord_inputs.dup : {}
      end

      private

      # Name a generated schema (inline block or list) as a controller constant
      # so it projects like a top-level schema. The default name (`:employee` ->
      # `EmployeeInput`) carries an `Input` suffix to avoid shadowing a same-named
      # model. Refuses to clobber a constant that isn't itself accord-generated —
      # pass `const:` to pick another name.
      def register_accord_schema(name, const)
        const = (const || "#{name.to_s.split(/[^a-zA-Z0-9]+/).map(&:capitalize).join}Input").to_s

        if const_defined?(const, false)
          existing = const_get(const)
          unless (existing.is_a?(Class) && existing < Schema) || existing.is_a?(ListSchema)
            raise ArgumentError,
                  "accord :#{name} would overwrite the existing constant #{const} — pass `const:` to choose another name"
          end
          remove_const(const)
        end

        const_set(const, yield)
      end
    end

    private

    # Override in a controller to customize the 422 response.
    def render_accord_errors(error)
      render json: { errors: error.errors.map(&:to_h) }, status: :unprocessable_entity
    end

    def accord_input(name, schema, from)
      @accord_input_cache ||= {}
      return @accord_input_cache[name] if @accord_input_cache.key?(name)

      @accord_input_cache[name] = schema.parse!(accord_source(from))
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
