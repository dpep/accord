# frozen_string_literal: true

module Accord
  # A declared validation rule. A field-scoped rule receives that field's
  # parsed value and reports errors against it; an unscoped rule receives no
  # argument and names the field it errors on explicitly.
  #
  #   validate(:salary) { |salary| error(:must_be_positive) if salary.negative? }
  #   validate { error(:end_before_start, field: :ends_at) if ends_at < starts_at }
  class Validation
    attr_reader :field, :block

    def initialize(field, block)
      @field = field
      @block = block
    end

    def scoped?
      !field.nil?
    end
  end
end
