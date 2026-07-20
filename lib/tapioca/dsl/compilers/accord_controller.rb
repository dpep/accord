# typed: false
# frozen_string_literal: true

# Auto-discovered by `tapioca dsl` when an app depends on both accord and
# tapioca. Inert (returns early) if Tapioca isn't loaded, so the file is safe to
# ship in the gem without making Tapioca a dependency.
return unless defined?(Tapioca::Dsl::Compiler)

require "accord"

module Tapioca
  module Dsl
    module Compilers
      # Generates RBI for the readers Accord defines on a controller, so
      # `employee.salary` type-checks inside an action. Covers both the `accord`
      # macro's named readers (`accord_inputs`) and the `accepts`/`returns` DSL's
      # readers (`accord_endpoints`) — the latter only when a reader name maps to
      # a single schema (a unique `as:`); the shared, polymorphic `input` reader
      # can't be typed and is skipped.
      class AccordController < Compiler
        # @override
        #: -> void
        def decorate
          readers = accord_readers
          return if readers.empty?

          root.create_path(constant) do |klass|
            readers.each { |name, input| klass.create_method(name.to_s, return_type: reader_return_type(input)) }
          end
        end

        class << self
          # @override
          #: -> T::Enumerable[Module]
          def gather_constants
            all_classes.select do |klass|
              (klass.respond_to?(:accord_inputs) && klass.accord_inputs.any?) ||
                (klass.respond_to?(:accord_endpoints) && klass.accord_endpoints.any?)
            end
          end
        end

        private

        # { reader_name => schema } for every typeable reader.
        def accord_readers
          readers = constant.respond_to?(:accord_inputs) ? constant.accord_inputs.dup : {}

          endpoints = constant.respond_to?(:accord_endpoints) ? constant.accord_endpoints.values : []
          endpoints.select(&:accepts?).group_by(&:reader).each do |reader, group|
            schemas = group.map(&:accepts).uniq
            readers[reader] = schemas.first if schemas.size == 1   # skip polymorphic readers
          end

          readers
        end

        def reader_return_type(input)
          if input.is_a?(::Accord::Schema::List)
            "T::Array[#{input.element.name || "T.untyped"}]"
          else
            input.name || "T.untyped"
          end
        end
      end
    end
  end
end
