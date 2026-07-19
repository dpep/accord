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
      # Generates RBI for the readers the `accord` controller macro defines, so
      # `employee.salary` type-checks inside an action. Reads the introspectable
      # `Controller.accord_inputs` registry — a schema reader returns that schema
      # instance, a `[Schema]` list reader returns `T::Array[Element]`.
      class AccordController < Compiler
        # @override
        #: -> void
        def decorate
          return if constant.accord_inputs.empty?

          root.create_path(constant) do |klass|
            constant.accord_inputs.each do |name, input|
              klass.create_method(name.to_s, return_type: reader_return_type(input))
            end
          end
        end

        class << self
          # @override
          #: -> T::Enumerable[Module]
          def gather_constants
            all_classes.select { |klass| klass.respond_to?(:accord_inputs) && klass.accord_inputs.any? }
          end
        end

        private

        def reader_return_type(input)
          if input.is_a?(::Accord::ListSchema)
            "T::Array[#{input.element.name || "T.untyped"}]"
          else
            input.name || "T.untyped"
          end
        end
      end
    end
  end
end
