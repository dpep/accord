# frozen_string_literal: true

module Accord
  # Declarative, composable, introspectable validators. A validator reports
  # structured violations (a code plus metadata) for a coerced value — never a
  # human-readable message, never rendering. It may also contribute OpenAPI
  # metadata. The field attaches path/field/value to build an Accord::Error.
  module Validators
    # Collects the violations a validator reports for one value.
    class Collector
      attr_reader :violations

      def initialize
        @violations = []
      end

      def add(code, **metadata)
        @violations << { code:, metadata: }
      end
    end

    class Base
      # @abstract Report violations for a coerced (non-nil) value.
      def validate(value, collector); end

      # OpenAPI metadata merged into the field's property schema.
      def openapi
        {}
      end

      # Validator name used in structured errors and introspection, e.g. :min.
      def name
        self.class.name.to_s.split("::").last.to_s.gsub(/([a-z])([A-Z])/, '\1_\2').downcase.to_sym
      end
    end

    # Presence is enforced by Field#resolve (missing-key handling). As a
    # validator, Required is declarative metadata (introspection, the OpenAPI
    # required list) and a no-op on a present value.
    class Required < Base
      def validate(_value, _collector); end
    end

    class Positive < Base
      def validate(value, collector)
        collector.add(:not_positive) unless value.positive?
      end
    end

    class Negative < Base
      def validate(value, collector)
        collector.add(:not_negative) unless value.negative?
      end
    end

    class NonZero < Base
      def validate(value, collector)
        collector.add(:zero) if value.zero?
      end
    end

    class Min < Base
      attr_reader :min

      def initialize(min)
        @min = min
      end

      def validate(value, collector)
        collector.add(:too_small, expected: min) if value < min
      end

      def openapi
        { minimum: min }
      end
    end

    class Max < Base
      attr_reader :max

      def initialize(max)
        @max = max
      end

      def validate(value, collector)
        collector.add(:too_large, expected: max) if value > max
      end

      def openapi
        { maximum: max }
      end
    end

    class Between < Base
      attr_reader :range

      def initialize(range)
        @range = range
      end

      def validate(value, collector)
        collector.add(:out_of_range, min: range.min, max: range.max) unless range.cover?(value)
      end

      def openapi
        { minimum: range.min, maximum: range.max }
      end
    end

    class Length < Base
      attr_reader :range

      def initialize(range)
        @range = range
      end

      def validate(value, collector)
        collector.add(:invalid_length, min: range.min, max: range.max) unless range.cover?(value.length)
      end

      def openapi
        { minLength: range.min, maxLength: range.max }
      end
    end

    class Inclusion < Base
      attr_reader :allowed

      def initialize(allowed)
        @allowed = allowed
      end

      def validate(value, collector)
        collector.add(:not_included, allowed:) unless allowed.include?(value)
      end

      def openapi
        { enum: allowed }
      end
    end

    class Exclusion < Base
      attr_reader :disallowed

      def initialize(disallowed)
        @disallowed = disallowed
      end

      def validate(value, collector)
        collector.add(:excluded, disallowed:) if disallowed.include?(value)
      end
    end

    class Format < Base
      attr_reader :pattern

      def initialize(pattern)
        @pattern = pattern
      end

      def validate(value, collector)
        collector.add(:invalid_format, pattern: pattern.source) unless value.match?(pattern)
      end

      def openapi
        { pattern: pattern.source }
      end
    end

    # A user-supplied inline rule:
    #   validate(:increment) { |value| error(:bad) unless (value % 100).zero? }
    class Custom < Base
      attr_reader :name

      def initialize(name, block)
        @name = name
        @block = block
      end

      def validate(value, collector)
        Proxy.new(collector).instance_exec(value, &@block)
      end

      # Exposes #error to the custom block, delegating to the collector.
      class Proxy
        def initialize(collector)
          @collector = collector
        end

        def error(code, **metadata)
          @collector.add(code, **metadata)
        end
      end
    end

    # Wraps a registered `|value, collector|` block as a named validator.
    class BlockValidator < Base
      attr_reader :name

      def initialize(name, block)
        @name = name
        @block = block
      end

      def validate(value, collector)
        @block.call(value, collector)
      end
    end

    # Maps validator names to a class (built with the DSL args) or a
    # `|value, collector|` block. The field-block DSL and positional flags
    # resolve names through here, so users can add their own standard validators.
    #
    #   Accord::Validators.register(:even) { |v, c| c.add(:odd) unless v.even? }
    #   Accord::Validators.register(:iban, IbanValidator)
    class Registry
      def initialize
        @factories = {}
      end

      def register(name, klass = nil, &block)
        raise ArgumentError, "provide a validator class or block" unless klass || block

        @factories[name.to_sym] = klass || block
        self
      end

      def registered?(name)
        @factories.key?(name.to_sym)
      end

      def build(name, *args)
        entry = @factories.fetch(name.to_sym) { raise ArgumentError, "unknown validator: #{name}" }
        entry.is_a?(Class) ? entry.new(*args) : BlockValidator.new(name.to_sym, entry)
      end

      def names
        @factories.keys
      end

      def clear
        @factories.clear
        self
      end

      def reset
        clear
        BUILTINS.each { |name, klass| register(name, klass) }
        self
      end
    end

    BUILTINS = {
      required: Required, positive: Positive, negative: Negative, non_zero: NonZero,
      min: Min, max: Max, between: Between, length: Length,
      inclusion: Inclusion, exclusion: Exclusion, format: Format,
    }.freeze

    class << self
      def registry
        @registry ||= Registry.new.reset
      end

      def register(...) = registry.register(...)
      def registered?(name) = registry.registered?(name)
      def build(name, *args) = registry.build(name, *args)
      def names = registry.names
      def clear = registry.clear
      def reset = registry.reset
    end
  end
end
