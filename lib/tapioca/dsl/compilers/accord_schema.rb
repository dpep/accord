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
      # Generates RBI for Accord::Schema subclasses so Sorbet knows the return
      # types of the dynamically-defined field readers. Reuses the same
      # per-field type mapping as Schema#rbs / Schema#rbi (Field#sorbet_return).
      class AccordSchema < Tapioca::Dsl::Compiler
        extend T::Sig

        ConstantType = type_member { { fixed: T.class_of(Accord::Schema) } }

        sig { override.returns(T::Enumerable[Module]) }
        def self.gather_constants
          descendants_of(Accord::Schema).reject { |klass| klass.name.nil? }
        end

        sig { override.void }
        def decorate
          return if constant.fields.empty?

          root.create_path(constant) do |klass|
            constant.fields.each_value do |field|
              klass.create_method(field.name.to_s, return_type: field.sorbet_return)
            end
          end
        end
      end
    end
  end
end
