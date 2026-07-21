# frozen_string_literal: true

require "set"
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

      # A nested schema — a named class, or an anonymous one declared inline with
      # a block (which can itself nest more anonymous objects/arrays). The block
      # form takes field options as keywords (`object :address, required: true do
      # … end`), since the block is the schema rather than a validator block.
      #   object :address, Address
      #   object :address do string :city end
      def object(name, schema = nil, *flags, **opts, &block)
        if schema.nil?
          raise ArgumentError, "object :#{name} needs a schema class or a block" unless block

          return register_field(ObjectField.new(name:, schema: Class.new(Schema, &block), **opts), flags)
        end
        unless schema.is_a?(Class) && schema < Schema
          raise ArgumentError, "object :#{name}: pass a schema class or a block (got #{schema.inspect}); for field options use keywords like `required: true`"
        end

        register_field(ObjectField.new(name:, schema:, **opts), flags, &block)
      end

      # A list whose element is a nested schema (named or an inline anonymous
      # block) or a scalar type. Each element is parsed at its index.
      #   array :employees, Employee     # list of objects
      #   array :tags, :string           # list of scalars
      #   array :phones do string :number end   # inline anonymous element
      def array(name, element = nil, *flags, **opts, &block)
        if element.nil? && block
          return register_field(ArrayField.new(name:, element: Class.new(Schema, &block), **opts), flags)
        end

        register_field(ArrayField.new(name:, element: array_element(name, element), **opts), flags, &block)
      end

      # Resolve an array's declared element to a Schema class or a Type instance,
      # failing fast on anything else.
      def array_element(name, element)
        return element if (element.is_a?(Class) && element < Schema) || element.is_a?(Type)
        return Types.build(element) if element.is_a?(Symbol) && Types.registered?(element)

        raise ArgumentError,
              "array :#{name} element must be a schema, a Type, or a registered type name — got #{element.inspect}"
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
        field.check_default!
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
        # A non-hash root (a JSON string/array/number) means the caller handed
        # parse the wrong thing — a programmer error, so fail fast rather than
        # manufacture per-field "missing" errors. (Nested non-hash values are
        # client input and stay collected as :invalid_object.)
        unless input.nil? || input.respond_to?(:key?)
          raise ArgumentError, "#{name || "schema"} expects a Hash-like input, got #{input.class}"
        end

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
          properties.merge!(field.openapi_properties)
          required.concat(field.openapi_required_keys)
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
      @present = Set.new
    end

    attr_reader :errors

    def valid?
      errors.empty?
    end

    # Whether a field's key was present in the input (even if its value was
    # explicitly null) — the absent/explicit-null distinction PATCH needs.
    def present?(name)
      @present.include?(name)
    end

    # The parsed values as a plain, deep Hash of typed Ruby values — nested
    # schemas and arrays recurse to Hashes too (so `to_h[:address]` is a Hash,
    # not an Accord::Schema). Use it to build a record (`Model.new(input.to_h)`);
    # use #dump for the canonical *external* form (strings) when serializing.
    #
    # `compact: true` drops absent fields but keeps explicit nulls — the PATCH
    # shape: `record.update(input.to_h(compact: true))` leaves untouched fields
    # alone and clears the ones sent as null.
    def to_h(compact: false)
      pairs = compact ? @values.select { |name, _| @present.include?(name) } : @values
      pairs.transform_values { |value| hashify(value, compact:) }
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
        present, = field.read(input)
        @present << field.name if present
        result = field.resolve(input, strict:, path:)
        @values[field.name] = result.value
        @errors.concat(result.errors)
      end

      self
    end

    private

    # Recurse nested schemas / arrays of schemas into plain Hashes for #to_h.
    def hashify(value, compact:)
      case value
      when Schema then value.to_h(compact:)
      when Array  then value.map { |element| hashify(element, compact:) }
      else value
      end
    end
  end

  # Generate the scalar DSL methods from the registered built-in types. Custom
  # types registered later add their own via Accord::Types.register.
  Types.names.each { |name| Schema.define_type_dsl(name) }
end
