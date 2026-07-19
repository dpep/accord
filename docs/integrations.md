# Integrations

Accord parses and validates **input**, and projects a schema into OpenAPI / RBS / RBI. Here's how it fits with common Ruby API tooling. (For OpenAPI + rswag, see [openapi.md](openapi.md).)

## GraphQL (graphql-ruby)

GraphQL already coerces scalar input, so reach for Accord where its built-in coercion isn't enough: richer validation, canonicalization (`"$1,000.00"` → `BigDecimal`), permissive parsing during a migration, or **sharing one contract** across REST and GraphQL.

A resolver receives its arguments as a hash — parse them through an Accord schema:

```ruby
class Mutations::CreateEmployee < GraphQL::Schema::Mutation
  argument :name, String, required: true
  argument :salary, String, required: true
  # ...

  field :employee, Types::EmployeeType, null: true
  field :errors, [Types::UserError], null: false

  def resolve(**args)
    input = CreateEmployee.parse(args)   # coerce + validate the GraphQL args

    if input.valid?
      { employee: EmployeeService.call(input), errors: [] }
    else
      { employee: nil, errors: user_errors(input.errors) }
    end
  end

  private

  # Accord::Error#path is an array — it maps straight onto a GraphQL error path.
  def user_errors(errors)
    errors.map { |e| { message: Accord::Messages.message(e), path: e.path, code: e.code } }
  end
end
```

You get one validation contract (the `Accord::Schema`) reused across every transport, with structured, localizable errors ([errors.md](errors.md)).

### Deserializing nested input

GraphQL input objects arrive as nested hashes, which `object`/`array` fields handle directly, producing nested error paths — no glue:

```ruby
class CreateOrder < Accord::Schema
  object :customer, CustomerInput
  array  :line_items, LineItemInput
end

CreateOrder.parse(args).errors.map(&:path)   # => [[:line_items, 2, :quantity], ...]
```

### Generating GraphQL input types (projection)

`Schema.graphql` projects a schema into GraphQL input-type SDL — the same idea as `Schema.openapi`/`Schema.rbs`. Scalars map to GraphQL scalars (`Int`, `Boolean`, `ISO8601Date`; decimals/UUIDs/etc. travel as `String`, matching `dump`), nested `object`/`array` fields become nested input types, `money` becomes a shared `MoneyInput`, and **required fields are non-null**:

```ruby
class Address < Accord::Schema
  string :city, :required
  string :country, :required
end

class CreateOrder < Accord::Schema
  string :email, :required
  object :address, Address, :required
  array  :line_items, LineItem
  money  :total
end

CreateOrder.graphql
# input CreateOrderInput {
#   email: String!
#   address: AddressInput!
#   line_items: [LineItemInput!]
#   total: MoneyInput
# }
```

`Schema.graphql_schemas` returns the whole graph (the root, every nested input type, and `MoneyInput`) keyed by name — join it into one SDL document:

```ruby
CreateOrder.graphql_schemas.values.join("\n\n")   # AddressInput, LineItemInput, MoneyInput, CreateOrderInput
```

`ISO8601Date`/`ISO8601DateTime` are graphql-ruby's date scalars; if you don't use them, treat those fields as `String`. Runnable example: [`examples/graphql.rb`](../examples/graphql.rb).

## RABL

RABL serializes objects **out**; Accord parses input **in** — they're complementary, meeting at two points.

**Echo canonical input.** `Schema#dump` is the inverse of parse — the canonical external representation — so serializing what you parsed is one call:

```ruby
input = CreateEmployee.parse!(params)
render json: input.dump   # => { name: "Ada", salary: "1000.00", hired_on: "2026-01-15", ... }
```

**Render the typed object.** A parsed input exposes accessors (`input.name`, `input.salary`), so a RABL template renders it like any object:

```ruby
# app/views/employees/show.rabl
object @input
attributes :name, :salary, :hired_on
```

`input.salary` is a `BigDecimal` there; for the canonical *string* form in the payload, use `Schema#dump` (above) or dump the field's type. Typically, though, RABL renders your **domain/model** object (the thing you built from the validated input), with Accord's job — turning untrusted params into that trusted input — already done. Runnable example: [`examples/rabl.rb`](../examples/rabl.rb).

---

See also: [rails.md](rails.md) · [openapi.md](openapi.md) · [errors.md](errors.md)
