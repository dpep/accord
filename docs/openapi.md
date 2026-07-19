# OpenAPI

The schema that parses and validates your input also **describes** it. Accord projects a schema into an OpenAPI object schema — properties, `required`, and validator-derived constraints — so the contract can't drift from the code that enforces it.

Accord generates the **data-contract schemas** (OpenAPI `components`). Paths/operations are your app's job (route it yourself, or let [rswag](#rswag) drive them from request specs).

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

## rswag

[rswag](https://github.com/rswag/rswag) generates Swagger/OpenAPI docs (and a UI) from request specs. Accord fills in the `components.schemas` half; rswag describes the paths. They connect through the shared components section.

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
      parameter name: :employee, in: :body, schema: { "$ref" => "#/components/schemas/CreateEmployee" }

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

---

See also: [validation.md](validation.md) · [types.md](types.md) · [rails.md](rails.md)
