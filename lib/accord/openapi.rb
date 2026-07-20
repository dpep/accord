# frozen_string_literal: true

require_relative "errors"

module Accord
  # Builds an OpenAPI 3 document from Accord::Endpoints — the paths section (from
  # each endpoint's verb/path + accepts/returns), the components.schemas graph,
  # and a shared components.responses/AccordErrors for the `:errors` response.
  # Pure: give it endpoints that already carry verb/path (the Rails layer fills
  # those from the router). See Accord.openapi_document.
  module OpenAPI
    ERRORS_REF = { "$ref" => "#/components/responses/AccordErrors" }.freeze

    # Reason phrases for a readable (and OpenAPI-required) response description.
    STATUS_TEXT = {
      200 => "OK", 201 => "Created", 202 => "Accepted", 204 => "No Content",
      400 => "Bad Request", 401 => "Unauthorized", 403 => "Forbidden",
      404 => "Not Found", 409 => "Conflict", 422 => "Unprocessable Entity",
    }.freeze

    module_function

    def document(endpoints, info:)
      routed = endpoints.select(&:routed?)
      doc = { openapi: "3.0.3", info:, paths: paths(routed) }
      components = components(routed)
      doc[:components] = components unless components.empty?
      doc
    end

    def paths(endpoints)
      endpoints.each_with_object({}) do |endpoint, paths|
        operations = paths[endpoint.path] ||= {}
        operations[endpoint.verb.to_s.downcase] = operation(endpoint)
      end
    end

    def operation(endpoint)
      op = { operationId: endpoint.key, responses: responses(endpoint) }
      op[:requestBody] = { required: true, content: json(schema_ref(endpoint.accepts)) } if endpoint.accepts?
      op
    end

    def responses(endpoint)
      return { "200" => { description: "OK" } } unless endpoint.returns?

      endpoint.returns.each_with_object({}) do |(status, contract), out|
        out[status.to_s] =
          case contract
          when :errors then ERRORS_REF
          when nil then { description: status_text(status) }                                # e.g. 204, no body
          else { description: status_text(status), content: json(schema_ref(contract)) }
          end
      end
    end

    def status_text(status)
      STATUS_TEXT[status] || status.to_s
    end

    def components(endpoints)
      schemas = {}
      uses_errors = false
      endpoints.each do |endpoint|
        collect(endpoint.accepts, schemas) if endpoint.accepts?
        endpoint.returns.each_value do |contract|
          next if contract.nil?

          contract == :errors ? (uses_errors = true) : collect(contract, schemas)
        end
      end

      components = {}
      components[:schemas] = schemas unless schemas.empty?
      components[:responses] = { "AccordErrors" => { description: "Validation errors", content: json(Error.openapi_response) } } if uses_errors
      components
    end

    # An OpenAPI schema reference for a contract: a `$ref` for a named schema, an
    # inline array for a list.
    def schema_ref(contract)
      case contract
      when ::Array then { type: "array", items: schema_ref(contract.first) }
      when Schema::List then contract.openapi
      else contract.openapi_ref
      end
    end

    def collect(contract, into)
      element = contract.is_a?(::Array) ? contract.first : contract
      element.openapi_schemas(into)
    end

    def json(schema)
      { "application/json" => { schema: } }
    end
  end
end
