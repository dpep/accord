# frozen_string_literal: true

require_relative "errors"
require_relative "field"
require_relative "fields/scalar"
require_relative "fields/object"
require_relative "fields/array"
require_relative "fields/money"
require_relative "types"

module Accord
  # A schema is the source of truth for an API boundary. The class declares the
  # contract (fields + declarative validators); an instance IS the parsed, typed
  # result — accessors return coerced values directly, with no wrappers.
  #
  #   class CreateEmployee < Accord::Schema
  #     string :name, required: true
  #     boolean :active, default: true
  #     currency :salary do
  #       positive
  #     end
  #   end
  #
  #   input = CreateEmployee.parse(params)
  #   input.valid?   # => true / false
  #   input.name     # => "Ada"
  #   input.errors   # => [Accord::Error, ...]
  #
  # Validation is declared in field blocks — see Field::Configurator.
  class Schema
    # Keyword options consumed by the field itself; every other keyword on a
    # scalar DSL call is forwarded to the type's constructor.
    FIELD_OPTIONS = %i[required default description example].freeze

    class << self
      def fields
        @fields ||= {}
      end

      # Subclasses inherit a copy of declared fields so extending a schema
      # doesn't mutate its parent.
      def inherited(subclass)
        super
        subclass.instance_variable_set(:@fields, fields.dup)
      end

      # Every schema descending from this one (recursively) — the discovery hook
      # for bulk export (RBS, OpenAPI, ...). Includes anonymous schemas (inline
      # controller inputs, one-offs); filter on `name` for just declared classes:
      #   Accord::Schema.descendants.select(&:name)
      def descendants
        subclasses.flat_map { |subclass| [subclass, *subclass.descendants] }
      end

      # Define a scalar DSL method for a registered type name (called for each
      # built-in at load, and by Accord::Types.register for custom types). After
      # the name come positional validator flags, then keyword options, then an
      # optional field block. Keywords are routed three ways:
      #   - field options (required/default/description/example) -> the field
      #   - registered validator names (format:/between:/length:/...) -> validators
      #   - anything else -> the type constructor (e.g. scale: on decimal)
      # so all three forms compose:
      #   string  :name, :required, length: 1..100
      #   string  :email, format: /@/
      #   decimal :price, scale: 2, between: 0..1000 do positive end
      def define_type_dsl(type_name)
        define_singleton_method(type_name) do |name, *flags, **opts, &block|
          field_opts = opts.slice(*FIELD_OPTIONS)
          # Field options win over same-named validators (e.g. `required:`).
          validator_opts = opts.except(*FIELD_OPTIONS).select { |key, _| Validators.registered?(key) }
          type_opts = opts.except(*FIELD_OPTIONS, *validator_opts.keys)

          field = ScalarField.new(name:, type: Types.build(type_name, **type_opts), **field_opts)
          validator_opts.each { |vname, arg| field.add_validator(Validators.build(vname, arg)) }
          register_field(field, flags, &block)
        end
      end

      # A nested schema. The parsed value is a sub-schema instance.
      #   object :address, Address
      def object(name, schema, *flags, **opts, &block)
        register_field(ObjectField.new(name:, schema:, **opts), flags, &block)
      end

      # A list of nested schemas. Each element is parsed through `schema`.
      #   array :employees, Employee
      def array(name, schema, *flags, **opts, &block)
        register_field(ArrayField.new(name:, schema:, **opts), flags, &block)
      end

      # An amount + currency parsed into a money-gem Money value.
      #   money :salary
      def money(name, *flags, **opts, &block)
        register_field(MoneyField.new(name:, **opts), flags, &block)
      end

      # Declare a scalar field backed by a Type. Public so custom types can be
      # registered directly. Positional flags and a block configure validators.
      def field(name, type, *flags, **opts, &block)
        register_field(ScalarField.new(name:, type:, **opts), flags, &block)
      end

      # Attach positional validator flags and a field block, then register.
      def register_field(field, flags, &block)
        flags.each { |flag| field.add_validator(Validators.build(flag)) }
        field.configure(&block)
        register(field)
      end

      # Register a field and define its reader.
      def register(field)
        fields[field.name] = field
        define_method(field.name) { @values[field.name] }
        field.name
      end

      # Parse untrusted input into a typed schema instance.
      #
      # Non-strict (the default, configurable via Accord.config.strict) collects
      # errors and normalizes legacy input. Strict raises on the first coercion
      # failure — for trusted callers. A per-call `strict:` overrides the config.
      def parse(input, strict: Accord.config.strict, path: [])
        new._parse(input || {}, strict:, path:)
      end

      # Parse and raise Accord::InvalidInput unless the result is valid — the
      # entry point for callers that want the typed input or a failure, with no
      # `.valid?` check (e.g. Rails controllers).
      def parse!(input, **options)
        parse(input, **options).tap do |result|
          raise InvalidInput, result unless result.valid?
        end
      end

      # Project this schema into an RBS class declaration, giving typed reader
      # signatures so `input.salary` is known to editors, Sorbet, and Steep — no
      # runtime dependency, just generated signatures. Required and defaulted
      # fields are non-nilable; optional fields are nilable (the valid-shape
      # contract). Nested schemas are referenced by class name.
      def rbs(class_name: name)
        raise ArgumentError, "cannot generate RBS for an anonymous schema — pass class_name:" if class_name.nil?

        signatures = fields.each_value.map do |field|
          "  def #{field.name}: () -> #{field.rbs_return}"
        end

        ["class #{class_name} < Accord::Schema", *signatures, "end"].join("\n")
      end

      # Project this schema into an OpenAPI object schema: properties (each field
      # contributes its type and any validator constraints), a `required` list,
      # and nested schemas referenced by `$ref`. Pair with #openapi_schemas for
      # the components section. See docs/openapi.md (including rswag).
      def openapi
        properties = {}
        required = []
        fields.each_value do |field|
          properties[field.name] = field.openapi
          required << field.name if field.required?
        end

        schema = { type: "object", properties: }
        schema[:required] = required unless required.empty?
        schema
      end

      # An OpenAPI `$ref` pointer to this schema's component — so hand-written
      # paths and rswag request specs reference the contract without retyping the
      # string: `parameter in: :body, schema: CreateEmployee.openapi_ref`.
      def openapi_ref
        raise ArgumentError, "cannot $ref an anonymous schema — give it a name" if name.nil?

        { "$ref" => "#/components/schemas/#{name}" }
      end

      # Every named schema in this schema's graph (itself plus nested object and
      # array schemas), keyed by class name — ready for an OpenAPI
      # `components: { schemas: ... }` section.
      def openapi_schemas(into = {})
        return into if name.nil? || into.key?(name)

        into[name] = openapi
        fields.each_value { |field| field.nested_schema&.openapi_schemas(into) }
        into
      end

      # Project this schema into a GraphQL input type (SDL). Each field maps to a
      # GraphQL type — scalars via their type, nested object/array fields to
      # nested input types (`AddressInput`, `[EmployeeInput!]`) — and required
      # fields are non-null. Pair with #graphql_schemas for the full document.
      # See docs/integrations.md.
      def graphql(type_name: graphql_input_name)
        raise ArgumentError, "cannot generate GraphQL for an anonymous schema — pass type_name:" if type_name.nil?

        lines = fields.each_value.map { |field| "  #{field.name}: #{field.graphql_type}" }
        ["input #{type_name} {", *lines, "}"].join("\n")
      end

      # The conventional GraphQL input type name for this schema, or nil for an
      # anonymous schema. Namespace separators are flattened (`Api::Employee` ->
      # `Api_Employee`) since `::` isn't legal in a GraphQL name, and the `Input`
      # suffix is added unless the name already carries it.
      def graphql_input_name
        return unless name

        base = name.gsub("::", "_")
        base.end_with?("Input") ? base : "#{base}Input"
      end

      # Every named GraphQL input type in this schema's graph (itself plus nested
      # object/array schemas and any MoneyInput), keyed by name — ready to join
      # into one SDL document: `Schema.graphql_schemas.values.join("\n\n")`.
      def graphql_schemas(into = {})
        return into if name.nil? || into.key?(name)

        into[name] = graphql
        fields.each_value { |field| field.graphql_schemas(into) }
        into
      end

      # Project this schema into a Sorbet RBI class declaration — the RBI sibling
      # of #rbs, for Sorbet-typed codebases. Prefer the bundled Tapioca DSL
      # compiler (auto-discovered by `tapioca dsl`) for Sorbet projects; this is
      # the manual/standalone form.
      def rbi(class_name: name)
        raise ArgumentError, "cannot generate RBI for an anonymous schema — pass class_name:" if class_name.nil?

        methods = fields.each_value.map do |field|
          "  sig { returns(#{field.sorbet_return}) }\n  def #{field.name}; end"
        end

        ["class #{class_name} < Accord::Schema", methods.join("\n\n"), "end"].join("\n")
      end
    end

    def initialize
      @values = {}
      @errors = []
    end

    attr_reader :errors

    def valid?
      errors.empty?
    end

    # The parsed values as a plain, deep Hash of typed Ruby values — nested
    # schemas and arrays recurse to Hashes too (so `to_h[:address]` is a Hash,
    # not an Accord::Schema). Use this to build a record (`Model.new(input.to_h)`);
    # use #dump for the canonical *external* form (strings) when serializing.
    def to_h
      @values.transform_values { |value| hashify(value) }
    end

    # The canonical external representation — the inverse of parse. Scalars dump
    # to canonical strings, nested schemas recurse. `to_h` gives typed Ruby
    # values; `dump` gives external (serializable) ones — render this as JSON.
    def dump
      self.class.fields.transform_values { |field| field.dump(@values[field.name]) }
    end

    def [](name)
      @values[name]
    end

    # @api private — resolves every field (coerce → validate) and aggregates the
    # errors. Public so Schema.parse can drive a freshly-allocated instance.
    def _parse(input, strict:, path:)
      self.class.fields.each_value do |field|
        result = field.resolve(input, strict:, path:)
        @values[field.name] = result.value
        @errors.concat(result.errors)
      end

      self
    end

    private

    # Recurse nested schemas / arrays of schemas into plain Hashes for #to_h.
    def hashify(value)
      case value
      when Schema then value.to_h
      when Array  then value.map { |element| hashify(element) }
      else value
      end
    end
  end

  # Generate the scalar DSL methods from the registered built-in types. Custom
  # types registered later add their own via Accord::Types.register.
  Types.names.each { |name| Schema.define_type_dsl(name) }
end
