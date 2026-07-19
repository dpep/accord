accord
======
![Gem](https://img.shields.io/gem/dt/accord?style=plastic)
[![codecov](https://codecov.io/gh/dpep/accord/branch/main/graph/badge.svg)](https://codecov.io/gh/dpep/accord)

Executable API contracts for Ruby.

One schema declaration is the source of truth for an API boundary: it parses untrusted input into canonical, typed Ruby values, validates it, collects structured errors, and projects itself into OpenAPI and RBS/RBI. Its home turf is the Rails controller — typed, validated request input, with no `permit` dance and no hand-written coercion.

```ruby
class CreateEmployee < Accord::Schema
  string :name, :required
  boolean :active, default: true
  currency :salary, :positive
end

class EmployeesController < ApplicationController
  accord :employee, CreateEmployee

  def create
    EmployeeService.call(employee)   # parsed + memoized on first use; 422 if invalid
    head :created
  end
end
```

The reader hands you coerced values directly — no wrappers, no strings to re-parse:

```ruby
employee.name    # => "Ada"
employee.active  # => true
employee.salary  # => BigDecimal("1000.00")
```

Invalid input raises `Accord::InvalidInput`, which Accord renders as a 422 for you. Prefer to handle it yourself? Parse permissively and inspect the errors:

```ruby
input = CreateEmployee.parse(params)
input.valid?                        # => false
input.errors.map(&:to_h)           # structured, render however you like
```

#### Features

- **A small, sharp type set.** Primitives (`string`, `boolean`, `integer`, `date`, `decimal`) plus semantic specializations that add parsing and canonicalization without new internals: `uuid`, `iso_currency`, `currency`, `duration`, `percentage`. Composite `money` (optional `money` gem) composes a decimal amount and an ISO currency. Decimals are always `BigDecimal`, never `Float`.
- **Two parsing modes, one engine.** `parse` is permissive — it accepts legacy formats (`"$1,000.00"` → `BigDecimal`), normalizes, and collects one structured error per bad field instead of raising. `parse!` (or `strict:`) raises on the first bad value, for trusted callers. `dump` always emits the canonical external form.
- **Declarative validation.** Rules live in field blocks (`length`, `between`, `inclusion`, `format`, …) or as positional flags (`string :name, :required`). Add your own inline or via a registry, usable by name in any schema.
- **Structured errors, not strings.** Every `Accord::Error` is data — `path`, `code`, `field`, `validator`, `value`, `metadata` — so rendering (JSON, GraphQL, i18n) stays a separate concern. Nested schemas produce nested paths (`[:employees, 2, :salary]`) with no special handling.
- **Rails integration, opt-in.** The core gem carries no Rails dependency. Require `accord/rails` and a Railtie adds the `accord` controller macro, 422 rendering, and permissive-parse events over `ActiveSupport::Notifications`.
- **Typing projections.** `Schema.rbs` and `Schema.rbi` generate typed reader signatures; a bundled Tapioca DSL compiler auto-generates RBI under `tapioca dsl`. Steep consumes the RBS, Sorbet the RBI — no manual conversion.
- **OpenAPI.** `Schema.openapi` generates an object schema — properties, `required`, and validator-derived constraints (`between 0..100` → `minimum`/`maximum`, `inclusion [...]` → `enum`), nested schemas by `$ref`. `Accord.openapi_schemas(...)` builds the components map, ready to feed [rswag](docs/openapi.md#rswag).

New here? Start with **[getting started](docs/getting_started.md)** — install to first schema in a few minutes — then the **[Rails guide](docs/rails.md)**. Or browse the runnable **[examples](examples/)**.

----
## Installation

```ruby
# Gemfile
gem "accord"
```

or

```sh
gem install accord
```

For Rails, require the integration:

```ruby
gem "accord", require: "accord/rails"
```

----
## A tour

The type DSL reads like the contract it is:

```ruby
class Employee < Accord::Schema
  string :name, :required
  uuid :id                          # canonical lowercase String
  currency :salary, :positive       # BigDecimal, scale 2
  duration :work_time, unit: :hours # BigDecimal, scale 2
  object :address, Address          # nested schema
end

class CreatePayroll < Accord::Schema
  array :employees, Employee        # array of nested schemas
end
```

Nested values parse into schema instances, and their errors bubble up as one flat list with precise paths:

```ruby
input = CreatePayroll.parse(params)
input.employees[2].salary          # => BigDecimal
input.errors.map(&:path)
# => [[:employees, 2, :salary], [:employees, 0, :address, :city]]
```

Where to go next:

| You want to... | Read |
|----------------|------|
| Install and write your first schema | [Getting started](docs/getting_started.md) |
| Use Accord in Rails controllers | [Rails](docs/rails.md) — the main guide |
| Understand the type system | [Types](docs/types.md) |
| Declare and register validators | [Validation](docs/validation.md) |
| Render structured errors | [Errors](docs/errors.md) |
| Generate OpenAPI / wire up rswag | [OpenAPI](docs/openapi.md) |
| Generate RBS / RBI for Sorbet or Steep | [Typing](docs/typing.md) |

## License

[MIT](LICENSE.txt)
