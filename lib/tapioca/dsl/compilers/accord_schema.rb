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
      #: [ConstantType = singleton(::Accord::Schema)]
      class AccordSchema < Compiler
        # @override
        #: -> void
        def decorate
          return if constant.fields.empty?

          root.create_path(constant) do |klass|
            constant.fields.each_value do |field|
              klass.create_method(field.name.to_s, return_type: field.sorbet_return)
            end

            # Type the parse entry points so `CreateEmployee.parse!(params)` is a
            # CreateEmployee (not T.untyped) with no T.let at the call site.
            %w[parse parse!].each do |entry|
              klass.create_method(
                entry,
                parameters: [
                  create_param("input", type: "T.untyped"),
                  create_kw_opt_param("strict", type: "T::Boolean", default: "Accord.config.strict"),
                  create_kw_opt_param("path", type: "T::Array[T.untyped]", default: "[]"),
                ],
                return_type: "T.attached_class",
                class_method: true,
              )
            end
          end
        end

        class << self
          # @override
          #: -> T::Enumerable[Module]
          def gather_constants
            descendants_of(::Accord::Schema).reject { |klass| klass.name.nil? }
          end
        end
      end
    end
  end
end
