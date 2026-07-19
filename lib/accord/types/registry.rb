# frozen_string_literal: true

module Accord
  # Registry of scalar types, keyed by DSL name. It drives the schema DSL — one
  # class method per registered type, generated from the registry rather than
  # written out by hand — and lets apps override a built-in or add a semantic
  # type, with the DSL method appearing automatically.
  #
  #   Accord::Types.register(:email, Email)            # adds `email :contact`
  #   Accord::Types.register(:boolean, StrictBoolean)  # overrides the built-in
  #
  # Type options declared on a field (`decimal :rate, scale: 8`) are forwarded
  # to the type's constructor; field options (required/default/...) are not.
  module Types
    class Registry
      def initialize
        @types = {}
      end

      def register(name, type_class)
        @types[name.to_sym] = type_class
        self
      end

      def registered?(name)
        @types.key?(name.to_sym)
      end

      def build(name, **options)
        @types.fetch(name.to_sym) { raise ArgumentError, "unknown type: #{name}" }.new(**options)
      end

      def names
        @types.keys
      end

      def clear
        @types.clear
        self
      end
    end

    class << self
      def registry
        @registry ||= Registry.new
      end

      # Register a type and expose its DSL method on Accord::Schema. Registering
      # an existing name overrides it — schemas defined afterward use the new
      # type (the DSL resolves the class at declaration time).
      def register(name, type_class)
        registry.register(name, type_class)
        Schema.define_type_dsl(name) if defined?(Schema)
        self
      end

      def registered?(name) = registry.registered?(name)
      def build(name, **options) = registry.build(name, **options)
      def names = registry.names
    end
  end
end
