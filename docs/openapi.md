# OpenAPI

The schema that parses and validates your input also **describes** it. Accord projects a schema into an OpenAPI object schema — properties, `required`, and validator-derived constraints — so the contract can't drift from the code that enforces it.

Two levels of generation:

- **Schemas** (`components`) — every `Accord::Schema` projects itself (below). Pair with your own paths, or feed [rswag](#rswag).
- **The whole document** (`paths` + `components`) — if you declare per-action contracts with the [`accepts`/`returns` DSL](rails.md#the-contract-dsl-accepts--returns), `Accord::ControllerHelpers.openapi_document` generates the complete spec (see [below](#the-whole-document-from-contracts)).

## `Schema.openapi`

Returns the OpenAPI object schema for a schema. Each field contributes its type; validators contribute constraints; nested schemas are referenced by `$ref`.

```ruby
class CreateEmployee < Accord::Schema
  string  :name, :required
  integer :age do
    between 18..120
  end
  string :status do
    inclusion %w[pending approved]
  end
  object :address, Address
end

CreateEmployee.openapi
# {
#   type: "object",
#   properties: {
#     name:    { type: "string" },
#     age:     { type: "integer", minimum: 18, maximum: 120 },
#     status:  { type: "string", enum: ["pending", "approved"] },
#     address: { "$ref" => "#/components/schemas/Address" },
#   },
#   required: [:name],
# }
```

Constraints flow straight from validators — `between` → `minimum`/`maximum`, `length` → `minLength`/`maxLength`, `inclusion` → `enum`, `format` → `pattern` (see [validation.md](validation.md#built-in-validators)). Add your own by giving a custom validator an `#openapi` method.

## `Schema.openapi_schemas` — components

Because nested schemas are `$ref`s, you also need their definitions. `openapi_schemas` walks the graph and returns every named schema keyed by class name — exactly the shape of an OpenAPI `components/schemas` block:

```ruby
CreateEmployee.openapi_schemas
# { "CreateEmployee" => { ... }, "Address" => { ... } }
```

Merge several roots with `Accord.openapi_schemas`:

```ruby
Accord.openapi_schemas(CreateEmployee, UpdateEmployee, EmployeeFilters)
# => a single { "CreateEmployee" => ..., "UpdateEmployee" => ..., "Address" => ..., ... }
```

Drop that under `components: { schemas: ... }` in your OpenAPI document and reference each with `$ref: "#/components/schemas/<Name>"`.

## The whole document, from contracts

If your controllers declare per-action contracts with [`accepts`/`returns`](rails.md#the-contract-dsl-accepts--returns), Accord generates the **entire** document — `paths` (verb and path from your routes, request body, responses), the `components.schemas` graph, and a shared `components.responses/AccordErrors` for every `422 => :errors`:

```ruby
# lib/tasks/openapi.rake
require "json"

Rails.application.eager_load!   # so every controller is loaded
doc = Accord::ControllerHelpers.openapi_document(info: { title: "API", version: "v1" })
File.write("openapi.json", JSON.pretty_generate(doc))
```

Verb and path come from `Rails.application.routes` (joined to each endpoint by `controller#action`); pass `resolver:` to override the routing source or scope generation. Nothing is stored, so the document can't drift — regenerate it in CI and diff. This is the "single source of truth" endgame: one declaration parses, validates, types, *and* documents each endpoint.

## rswag

[rswag](https://github.com/rswag/rswag) generates Swagger/OpenAPI docs (and a UI) from request specs. Accord fills in the `components.schemas` half; rswag describes the paths. They connect through the shared components section. (If you use the [contract DSL](#the-whole-document-from-contracts), Accord already emits the paths — rswag then only *verifies* the generated doc against real requests, rather than authoring it.)

**1. Register Accord's schemas as components** in `spec/swagger_helper.rb`:

```ruby
require "accord"
require_relative "../app/schemas/create_employee"   # etc.

RSpec.configure do |config|
  config.openapi_root = Rails.root.join("swagger").to_s

  config.openapi_specs = {
    "v1/swagger.yaml" => {
      openapi: "3.0.1",
      info: { title: "API", version: "v1" },
      components: {
        schemas: Accord.openapi_schemas(CreateEmployee, EmployeeFilters),
      },
      paths: {},
    },
  }
end
```

**2. Reference them by `$ref`** in a request spec — the request body and responses reuse the same contract your controller enforces:

```ruby
# spec/requests/employees_spec.rb
require "swagger_helper"

RSpec.describe "Employees", type: :request do
  path "/employees" do
    post "Create an employee" do
      consumes "application/json"
      parameter name: :employee, in: :body, schema: CreateEmployee.openapi_ref   # => { "$ref" => "#/components/schemas/CreateEmployee" }

      response "201", "created" do
        let(:employee) { { name: "Ada", salary: "50000" } }
        run_test!
      end

      response "422", "invalid" do
        let(:employee) { { salary: "-5" } }
        run_test!
      end
    end
  end
end
```

**3. Generate the doc:**

```sh
bundle exec rake rswag:specs:swaggerize
```

The result is a single OpenAPI document whose request/response schemas are generated from the same `Accord::Schema`s that parse and validate the requests at runtime — one source of truth for the contract.

> **Keeping it in sync.** Because the components come from `Accord.openapi_schemas(...)`, adding a field or a validator updates the generated doc automatically — no hand-maintained schema YAML to drift.

## Exporting the components to a file

Accord builds the `components.schemas` map (not paths — those are your routes' concern). Write it out in a rake task or script; discover every declared schema with `Accord::Schema.descendants`:

```ruby
require "json"

schemas = Accord::Schema.descendants.select(&:name)   # or list them explicitly
components = { components: { schemas: Accord.openapi_schemas(*schemas) } }
File.write("openapi.components.json", JSON.pretty_generate(components))
```

Merge that under your hand-written `paths`/`info`, or let rswag assemble the full document from request specs (above).

---

See also: [validation.md](validation.md) · [types.md](types.md) · [rails.md](rails.md)
