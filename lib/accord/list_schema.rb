# frozen_string_literal: true

require_relative "errors"
require_relative "fields/array"

module Accord
  # A list of a schema — the projectable, parseable form of `[CreateEmployee]`.
  # A Schema is always an object (named properties); a list is a top-level JSON
  # array, so it's its own thing. Parsing runs each element through the element
  # schema at its index (errors read `[2, :salary]`, no wrapper key), and every
  # projection is array-shaped, delegated to an ArrayField over the element so
  # OpenAPI/RBS/RBI/GraphQL match the field form exactly.
  #
  #   people = Accord::ListSchema.new(Employee)
  #   people.parse!([{ name: "Ada" }, { name: "Bo" }])   # => [Employee, Employee]
  #   people.openapi                                       # => { type: "array", items: {...} }
  class ListSchema
    # The outcome of parsing a list: the parsed element instances plus their
    # aggregated errors. Enumerable over the members, so it reads like an array.
    class Result
      include Enumerable

      attr_reader :members, :errors

      def initialize(members, errors = members.flat_map(&:errors))
        @members = members
        @errors = errors
      end

      def valid?
        errors.empty?
      end

      def each(&) = members.each(&)
      def to_a = members.dup
      def size = members.size
      def [](index) = members[index]
    end

    attr_reader :element

    def initialize(element)
      @element = element
      # A representative field: not parsed through (elements are parsed directly
      # for clean paths), only its array-shaped projections are reused.
      @field = ArrayField.new(name: :items, schema: element, required: true)
    end

    # Parse a bare array; each element is parsed at its index so errors carry it
    # (`[2, :field]`). Never fails fast — aggregates every element's errors.
    def parse(source, strict: Accord.config.strict, path: [])
      items = source.nil? ? [] : source
      unless items.is_a?(Array)
        return Result.new([], [Error.new(path:, code: :invalid_array, input: source)])
      end

      Result.new(items.each_with_index.map { |item, index| element.parse(item, strict:, path: path + [index]) })
    end

    # Parse and return the element instances, raising Accord::InvalidInput
    # unless every element is valid. (Non-bang #parse returns the richer Result
    # with errors; the valid list is just its members.)
    def parse!(source, **options)
      result = parse(source, **options)
      raise InvalidInput, result unless result.valid?

      result.members
    end

    def openapi = @field.openapi
    def rbs = @field.rbs
    def sorbet = @field.sorbet
    def graphql = @field.graphql_type

    # The element's components/input types — a list introduces no named type of
    # its own; it's `[Element]`.
    def openapi_schemas(into = {}) = element.openapi_schemas(into)
    def graphql_schemas(into = {}) = @field.graphql_schemas(into)
  end
end
