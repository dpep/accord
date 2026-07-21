# frozen_string_literal: true

require_relative "errors"
require_relative "schema"
require_relative "schema/list"
require_relative "endpoint"
require_relative "openapi"

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
      # Strict mode raises on the first bad/missing value instead of collecting;
      # at a request boundary that's still client bad data — render it as a 422.
      base.rescue_from(Accord::MissingField) { |e| render_accord_errors(accord_fault_result(:required, field: e.field, path: [e.field])) }
      base.rescue_from(Accord::CoercionError) { |e| render_accord_errors(accord_fault_result(e.code, input: e.input)) }
    end

    # Enumerate every controller's declared inputs, keyed by controller name:
    #   { "EmployeesController" => { employee: CreateEmployee, batch: Schema::List }, ... }
    # Discovery walks ActionController::Base.descendants, so eager-load the app
    # first (`Rails.application.eager_load!`); pass an explicit list to scope it.
    # The introspection hook for contract tooling and docs. Note this is
    # per-controller (reader -> schema), not per-action — binding a reader to an
    # action/verb would need an explicit annotation on the macro.
    def self.controller_inputs(controllers = discover_controllers)
      controllers
        .select { |controller| controller.respond_to?(:accord_inputs) && controller.name && controller.accord_inputs.any? }
        .to_h { |controller| [controller.name, controller.accord_inputs] }
    end

    def self.discover_controllers
      defined?(::ActionController::Base) ? ::ActionController::Base.descendants : []
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
      # projectable Schema::List constant, just like an inline block.
      # `strict:` overrides the parse mode for this input (defaults to
      # Accord.config.strict) — a per-endpoint strict boundary that rejects loose
      # input, without leaving the macro for a manual `Schema.parse!` call. Loose
      # or missing input on a strict input renders a 422 like any other bad data.
      def accord(name, schema = nil, from: nil, const: nil, strict: nil, &block)
        input =
          if block
            raise ArgumentError, "accord :#{name} takes a schema or a block, not both" if schema

            register_accord_schema(name, const) { Class.new(Schema, &block) }
          elsif schema.nil?
            raise ArgumentError, "accord :#{name} requires a schema class or a block"
          elsif schema.is_a?(Array)
            raise ArgumentError, "accord :#{name}: a list source takes exactly one schema, e.g. [CreateEmployee]" if schema.size != 1

            register_accord_schema(name, const) { Schema::List.new(schema.first) }
          elsif const
            raise ArgumentError, "accord :#{name}: `const:` only applies to an inline (block) or list schema"
          else
            schema
          end

        accord_inputs[name] = input
        define_method(name) { accord_input(name, input, from, strict) }
      end

      # The inputs declared on this controller, as `{ reader_name => schema }`
      # (a schema class, or an Accord::Schema::List for a `[Schema]` list). Fully
      # introspectable — and the source the Tapioca controller compiler types the
      # generated readers from. A subclass inherits its parents' declarations.
      def accord_inputs
        @accord_inputs ||= superclass.respond_to?(:accord_inputs) ? superclass.accord_inputs.dup : {}
      end

      # --- accepts / returns: the per-action contract DSL --------------------
      # Sig-style decorators that bind to the *next* `def`. `accepts` declares the
      # request schema (a class, a `[Schema]` list, or a block) and defines the
      # input reader; `returns` declares `status => contract`. Both compose, both
      # optional. See Accord::Endpoint / #accord_endpoints for the result.
      #
      #   accepts CreateEmployee, as: :employee
      #   returns 201 => EmployeeView, 422 => :errors
      #   def create; ...; end

      # The request contract for the next action. `as:` names the reader (default
      # Accord.config.input_reader, e.g. `input`); `from:`/`strict:` mirror the
      # `accord` macro. A block declares an anonymous schema.
      def accepts(schema = nil, from: nil, as: nil, strict: nil, &block)
        raise ArgumentError, "accepts takes a schema or a block, not both" if block && schema
        raise ArgumentError, "accepts needs a schema or a block" if schema.nil? && block.nil?

        accord_pending_slot[:accepts] = { schema:, block:, from:, as:, strict: }
        nil
      end

      # The response contract(s) for the next action — `returns(200 => View, 422
      # => :errors)`, or `returns(201) { ... }` for an anonymous response schema.
      def returns(responses = nil, &block)
        slot = (accord_pending_slot[:returns] ||= {})
        if block
          slot[Integer(responses)] = { block: }
        else
          responses.each { |status, contract| slot[Integer(status)] = { contract: } }
        end
        nil
      end

      # Group the enclosed accepts/returns under an API version (a single
      # controller serving multiple versions). The reader parses the version
      # matching the request; each version projects to its own OpenAPI document.
      #
      #   version 1 do accepts V1::Create; returns 200 => V1::View end
      #   version 2 do accepts V2::Create; returns 200 => V2::View end
      def version(number)
        raise ArgumentError, "version blocks don't nest" if @accord_version

        @accord_version = number
        yield
      ensure
        @accord_version = nil
      end

      # This controller's declared operations — an Array of Accord::Endpoint (one
      # per action, or per action+version). Introspectable, inherited.
      def accord_endpoints
        @accord_endpoints ||= superclass.respond_to?(:accord_endpoints) ? superclass.accord_endpoints.dup : []
      end

      # @api private — Ruby's hook, fired after every `def`. When accepts/returns
      # are pending, bind them (per version) to this action and clear the slots.
      def method_added(action)
        super
        pending = @accord_pending
        return if pending.nil? || pending.empty?

        @accord_pending = nil
        pending.each { |version, slot| build_accord_endpoint(action, slot, version) }
        define_accepts_reader(action, pending)
      end

      private

      # Pending accepts/returns for the current version context (nil = unversioned).
      def accord_pending_slot
        (@accord_pending ||= {})[@accord_version] ||= {}
      end

      # Name a generated schema (inline block or list) as a controller constant
      # so it projects like a top-level schema. The default name (`:employee` ->
      # `EmployeeInput`) carries an `Input` suffix to avoid shadowing a same-named
      # model. Refuses to clobber a constant that isn't itself accord-generated —
      # pass `const:` to pick another name.
      def register_accord_schema(name, const)
        const = (const || "#{name.to_s.split(/[^a-zA-Z0-9]+/).map(&:capitalize).join}Input").to_s

        if const_defined?(const, false)
          existing = const_get(const)
          unless (existing.is_a?(Class) && existing < Schema) || existing.is_a?(Schema::List)
            raise ArgumentError,
                  "accord :#{name} would overwrite the existing constant #{const} — pass `const:` to choose another name"
          end
          remove_const(const)
        end

        const_set(const, yield)
      end

      # Assemble one Endpoint for an action+version from its pending slot.
      def build_accord_endpoint(action, slot, version)
        accepts = slot[:accepts]
        schema = accepts && resolve_accepts_schema(action, accepts, version)

        accord_endpoints << Endpoint.new(
          controller: name, action:, version:, accepts: schema,
          returns: resolve_returns(action, slot[:returns] || {}, version),
          from: accepts && accepts[:from], strict: accepts && accepts[:strict],
          reader: (accepts && accepts[:as]) || Accord.config.input_reader, verb: nil, path: nil,
        )
      end

      # Define the (version-dispatched) input reader for an action, once, if any
      # version declares an accepts. Several actions sharing the default name
      # don't clobber — the reader resolves the current action + request version.
      def define_accepts_reader(action, pending)
        accepts = pending.values.filter_map { |slot| slot[:accepts] }.first
        return unless accepts

        reader = accepts[:as] || Accord.config.input_reader
        define_method(reader) { accord_action_input } unless method_defined?(reader)
      end

      # A schema class, a Schema::List for `[Schema]`, or a block named after the
      # action + version (`create` -> `CreateInput`, `create`@2 -> `CreateV2Input`).
      def resolve_accepts_schema(action, accepts, version = nil)
        suffix = version ? "V#{version}Input" : "Input"
        if accepts[:block]
          register_accord_schema(action, "#{accord_camelize(action)}#{suffix}") { Class.new(Schema, &accepts[:block]) }
        elsif accepts[:schema].is_a?(Array)
          raise ArgumentError, "accepts [Schema] takes exactly one schema" if accepts[:schema].size != 1

          Schema::List.new(accepts[:schema].first)
        else
          accepts[:schema]
        end
      end

      def resolve_returns(action, pending, version = nil)
        suffix = version ? "V#{version}Response" : "Response"
        pending.transform_values do |spec|
          if spec[:block]
            register_accord_schema(action, "#{accord_camelize(action)}#{suffix}") { Class.new(Schema, &spec[:block]) }
          else
            spec[:contract]
          end
        end
      end

      def accord_camelize(name)
        name.to_s.split(/[^a-zA-Z0-9]+/).map(&:capitalize).join
      end
    end

    # Enumerate every controller's declared operations across the app (eager-load
    # first). The registry an OpenAPI-paths generator / contract tooling reads.
    def self.endpoints(controllers = discover_controllers)
      controllers
        .select { |c| c.respond_to?(:accord_endpoints) && c.name }
        .flat_map { |c| c.accord_endpoints.map { |endpoint| endpoint.with(controller: c.name) } }
    end

    # Generate a full OpenAPI 3 document from the declared `accepts`/`returns`
    # contracts — paths, components, and the shared AccordErrors response. Verb
    # and path come from the router via `resolver` (a `->(controller, action) {
    # [verb, path] }`), defaulting to Rails' routes; inject one to test or to
    # scope generation. `Accord.freeze!` / eager-load first for a complete doc.
    # Pass `version:` to scope the document to one API version (header versioning
    # can't vary a body by header in a single operation, so each version is its
    # own document) — unversioned endpoints are always included.
    def self.openapi_document(info:, version: nil, endpoints: self.endpoints, resolver: rails_route_resolver)
      selected = version.nil? ? endpoints : endpoints.select { |e| e.version.nil? || e.version.to_s == version.to_s }
      resolved = selected.map do |endpoint|
        verb, path = resolver.call(endpoint.controller, endpoint.action)
        verb && path ? endpoint.with(verb:, path:) : endpoint
      end
      Accord::OpenAPI.document(resolved, info:)
    end

    # A resolver over Rails' routes: controller class name + action -> [verb,
    # OpenAPI path]. Returns nils outside Rails.
    def self.rails_route_resolver
      routes = defined?(::Rails) && ::Rails.respond_to?(:application) && ::Rails.application ? ::Rails.application.routes.routes : []
      lambda do |controller, action|
        route = routes.find { |r| r.defaults[:controller] == rails_controller_path(controller) && r.defaults[:action] == action.to_s }
        route ? [route.verb, openapi_path(route.path.spec.to_s)] : nil
      end
    end

    # "Admin::EmployeesController" -> "admin/employees"
    def self.rails_controller_path(controller_name)
      controller_name.to_s.sub(/Controller\z/, "").gsub("::", "/").gsub(/([a-z\d])([A-Z])/, '\1_\2').downcase
    end

    # "/employees/:id(.:format)" -> "/employees/{id}"
    def self.openapi_path(spec)
      spec.sub(/\(\.:format\)\z/, "").gsub(/:(\w+)/, '{\1}')
    end

    private

    # The parsed input for the current action + request version, from its
    # `accepts` contract — memoized, raises InvalidInput (rendered 422) on invalid
    # input.
    def accord_action_input
      action = action_name.to_sym
      version = accord_api_version
      candidates = self.class.accord_endpoints.select { |e| e.action == action && e.accepts? }
      endpoint = candidates.find { |e| e.version.to_s == version.to_s } || candidates.find { |e| e.version.nil? }
      raise ArgumentError, "no accord `accepts` contract for #{action_name} (version #{version.inspect})" unless endpoint

      @accord_input_cache ||= {}
      @accord_input_cache[[action, version]] ||= endpoint.accepts.parse!(
        accord_source(endpoint.from), **(endpoint.strict.nil? ? {} : { strict: endpoint.strict }),
      )
    end

    # The request's API version: the configured resolver proc, else the version
    # header (`Accord.config.version_header`). Override per-controller if neither
    # fits. nil for an unversioned request.
    def accord_api_version
      resolver = Accord.config.version_resolver
      return resolver.call(self) if resolver
      return request.headers[Accord.config.version_header] if respond_to?(:request) && request

      nil
    end

    # Override in a controller to customize the 422 response.
    def render_accord_errors(error)
      render json: { errors: error.errors.map(&:to_h) }, status: :unprocessable_entity
    end

    # Wrap a strict-mode fault as one carrying a single structured error, so
    # render_accord_errors sees the same `.errors` interface as InvalidInput.
    def accord_fault_result(code, field: nil, path: [], input: nil)
      errors = [Accord::Error.new(path:, field:, code:, input:)]
      Struct.new(:errors).new(errors)
    end

    def accord_input(name, schema, from, strict = nil)
      @accord_input_cache ||= {}
      return @accord_input_cache[name] if @accord_input_cache.key?(name)

      options = strict.nil? ? {} : { strict: }
      @accord_input_cache[name] = schema.parse!(accord_source(from), **options)
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
