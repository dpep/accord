# Accord

Executable API contracts for Ruby.

A schema is the source of truth for an API boundary. One declaration describes the accepted input, coerces it into typed Ruby objects, validates it, collects structured errors, and (later) documents the contract.

```ruby
class CreateEmployee < Accord::Schema
  string :name, required: true
  boolean :active, default: true
  currency :salary

  validate(:salary) { |salary| error(:must_be_positive) if salary.negative? }
end

input = CreateEmployee.parse(params)

if input.valid?
  EmployeeService.call(input)
else
  render json: input.errors.map(&:to_h), status: :unprocessable_entity
end
```

Accessors return coerced values directly — no wrappers:

```ruby
input.name    # => "Ada"
input.active  # => true
input.salary  # => #<BigDecimal ...>
```

## Parsing modes

Two modes, one coercion engine.

**Permissive** (`parse`, the default) — for API migration. Accepts legacy formats, normalizes values, and collects a structured error per bad field instead of raising.

```ruby
input = CreateEmployee.parse({ salary: "$1,000.00" })
input.salary            # => 0.1e4 (BigDecimal)
```

**Strict** (`parse(..., strict: true)`) — for trusted callers. Raises on the first invalid value or missing required field.

```ruby
Accord::Types::Currency.parse!("$abc")   # => raises Accord::CoercionError
```

## Field types

Each type implements a common interface: `parse` (permissive), `parse!` (strict), `dump`, and `openapi`.

| Type | Permissive accepts | Strict accepts | Internal |
|------|--------------------|----------------|----------|
| `string`   | String, Symbol, Numeric        | String                     | `String` |
| `uuid`     | RFC 4122 UUID (any case)       | RFC 4122 UUID              | `String` (canonical lowercase) |
| `boolean`  | `true`/`false`, `"true"`/`"false"`, `"1"`/`"0"`, `"yes"`/`"no"` | `true`/`false` | `true`/`false` |
| `integer`  | Integer, integer strings, whole Floats | Integer            | `Integer` |
| `date`     | Date, Time, ISO-8601, configured legacy `formats:` | Date, Time, ISO-8601 | `Date` |
| `decimal`  | numeric strings, Integer, Float | numeric strings, Integer  | `BigDecimal` |
| `currency` | `"10"`, `"$10.50"`, `"1,000.00"`, Integer, Float | plain numeric strings, Integer | `BigDecimal` |
| `duration` | plain numbers                  | plain numbers, Integer     | `BigDecimal` |
| `percentage` | plain numbers                | plain numbers, Integer     | `BigDecimal` |

Decimals are always `BigDecimal`, never `Float` — Floats are rejected in strict mode and routed through their string form otherwise, so binary rounding never enters the pipeline. `decimal`/`currency`/`duration` take a `scale:` (decimal places), enforced on parse; excess precision is rejected unless `round: true` is set. `dump` renders exactly `scale` places.

### Primitives and semantic types

The type system is a small set of primitives (`String`, `Boolean`, `Date`, `Decimal`) plus **semantic specializations** that add parsing, canonicalization, defaults, and OpenAPI metadata without introducing new internal representations. **Composite** types (`Money`) compose scalars rather than adding a primitive:

```
String              Decimal            Composite
├── UUID            ├── Currency       └── Money  (Decimal + ISOCurrency)
└── ISOCurrency     ├── Duration
                    └── Percentage
```

```ruby
uuid :id                          # canonical lowercase String
iso_currency :currency            # canonical uppercase ISO-4217 String
currency :salary                  # BigDecimal, scale 2
duration :work_time, unit: :hours # BigDecimal, scale 2
decimal :exchange_rate, scale: 8  # BigDecimal, scale 8
```

### Money

`money` parses an amount + currency into a [`money`](https://rubygems.org/gems/money)-gem `Money` value. It composes `Decimal` (amount) and `ISOCurrency` (currency), so errors nest exactly like any other sub-structure — `[:salary, :amount]`, `[:salary, :currency]` — with no special cases.

```ruby
class Payroll < Accord::Schema
  money :salary                                # nested: { amount:, currency: }
  money :bonus, format: :flat                  # flat: bonus + bonus_currency siblings
  money :stipend, currency: "USD"              # fixed currency, amount only
end

Payroll.parse(salary: { amount: "1234.50", currency: "usd" }).salary
# => #<Money fractional:123450 currency:USD>
```

The amount's precision is **currency-aware**: it's validated against the currency's subunit exponent (USD → 2, JPY → 0, BHD → 3), so `{ amount: "1234.5", currency: "JPY" }` is rejected while `{ amount: "1.234", currency: "BHD" }` is accepted. `dump` always emits the canonical nested form (`{ amount: "1234.50", currency: "USD" }`) regardless of input format, and `openapi` produces an object schema reusing the component scalars.

The `money` gem is an **optional dependency** — only `money` and `iso_currency` need it, and they require it lazily. Add `gem "money"` to your Gemfile to use them.

## Nested schemas

Compose schemas with `object` and `array`:

```ruby
class Address < Accord::Schema
  string :city, required: true
  string :zip
end

class Employee < Accord::Schema
  string :name, required: true
  currency :salary
  object :address, Address
end

class CreatePayroll < Accord::Schema
  array :employees, Employee
end
```

Nested values are parsed schema instances, and errors bubble up as one flat list with precise paths:

```ruby
input = CreatePayroll.parse(params)
input.employees[2].salary          # => BigDecimal
input.errors.map(&:path)
# => [[:employees, 2, :salary], [:employees, 0, :address, :city]]
```

## Typing (RBS)

Because every field knows its internal type, a schema can project itself into an RBS class declaration — typed reader signatures that Sorbet, Steep, and editors understand, with no runtime dependency:

```ruby
CreateEmployee.rbs
# class CreateEmployee < Accord::Schema
#   def name: () -> String
#   def active: () -> bool
#   def salary: () -> BigDecimal?
#   def address: () -> Address?
# end
```

Required and defaulted fields are non-nilable; optional fields are nilable (the valid-shape contract). Typing is a *projection* of the schema, the same pattern as OpenAPI — see [docs/design.md](docs/design.md).

**Steep** consumes the `.rbs` directly — write it into `sig/`. **Sorbet** reads RBI, so Accord also projects `Schema.rbi` and ships a **Tapioca DSL compiler**: in a project with `tapioca`, `tapioca dsl` auto-discovers it and generates typed reader RBI for every schema — no manual conversion. Both paths share one type mapping (`Field#sorbet_return` / `#rbs_return`).

## Validation

Validation is declarative — rules are declared in field blocks and produce structured errors, never messages. The lifecycle is per-field and never fails fast: **parse → canonicalize → validate → collect → continue**, so every error surfaces in one pass.

```ruby
class CreateEmployee < Accord::Schema
  string :name do
    required
    length 1..100
  end

  integer :age do
    between 18..120
  end

  currency :salary do
    positive
    validate(:increment) { |v| error(:bad_increment) unless (v % 100).zero? }  # custom inline
  end

  string :status do
    inclusion %w[pending approved rejected]
  end
end
```

Built-in validators: `required`, `min`, `max`, `between`, `positive`, `negative`, `non_zero`, `length`, `inclusion`, `exclusion`, `format`. Custom rules are inline `validate` blocks or reusable `Accord::Validators::Base` subclasses (`validator MyValidator`). Validators are introspectable (`CreateEmployee.fields[:salary].validators`) and contribute OpenAPI (`between 0..100` → `minimum`/`maximum`, `length 1..50` → `minLength`/`maxLength`, `inclusion [...]` → `enum`).

## Errors

Errors are first-class structured data (`Accord::Error`) — never rendered strings. Each carries `path`, `code`, `field` (the last path segment), and, for validation failures, `validator`, `value`, and validator-specific metadata (`expected`, `min`, `max`, …). Rendering (Rails JSON, GraphQL, i18n, logs) is a separate concern. Paths are arrays, so nested schemas point at `[:employees, 2, :salary]` with no special handling.

```ruby
input.errors.first.to_h
# => { path: [:discount], field: :discount, code: :too_small, validator: :min, value: -5, expected: 0 }
```

## Rails integration

Opt-in and decoupled — the core gem carries no Rails or ActiveSupport dependency. Load it with:

```ruby
gem "accord", require: "accord/rails"
```

This wires permissive-parse events to `ActiveSupport::Notifications` and makes the `accord` macro available in controllers:

```ruby
class EmployeesController < ApplicationController
  accord :employee, CreateEmployee

  def create
    EmployeeService.call(employee)   # parsed + memoized on first use; 422 if invalid
    head :created
  end
end
```

`accord` declares a lazily-parsed, memoized reader — decoupled from action names, so a controller can declare several inputs and each action uses whichever it needs. `from:` scopes the source (defaults to `params`):

```ruby
accord :filters, EmployeeFilters, from: -> { params[:q] }
```

Prefer calling the schema directly? It's the entry point — `CreateEmployee.parse!(params)` returns the typed input or raises. Either way, invalid input raises `Accord::InvalidInput`, rendered as a 422 by a `rescue_from` installed on include. The schema *is* the allowlist (it reads only declared fields via `[]`/`key?`, which `ActionController::Parameters` permits without `permit`), so params are consumed unfiltered.

Customize the response by overriding one method:

```ruby
class ApplicationController < ActionController::API
  include Accord::ControllerHelpers

  def render_accord_errors(error)
    render json: ErrorSerializer.new(error.errors), status: :unprocessable_entity
  end
end
```

## Configuration

```ruby
Accord.configure do |c|
  c.strict = false   # default parse mode; per-call strict: always wins
end
```

The shipped default is non-strict — an API boundary tolerates and reports; strict raises on the first coercion failure, for trusted internal callers.

Every tolerated error in permissive mode emits an event you can subscribe to:

```ruby
ActiveSupport::Notifications.subscribe(/accord\.parse/) do |name, *, payload|
  # name    => "accord.parse.invalid_currency"
  # payload => { field: :salary, path: [:salary], input: "$abc" }
end
```

## Roadmap

- **Milestone 1 — Core types** ✅ Schema, Field, typed input object, String / Boolean / Date / Currency, Error objects. No Rails dependency.
- **Milestone 2 — Nested schemas** ✅ `object` and `array` fields, nested error paths.
- **Milestone 3 — Rails integration** ✅ controller helpers, `ActiveSupport::Notifications`, params handling. _Refinement in progress: declarative macro, default-mode config, overridable rendering._
- **Milestone 4 — Typing projection** ✅ `Schema.rbs` generates RBS signatures for the parsed result, so `input.salary` is a known `BigDecimal` to Sorbet/Steep/editors — no runtime dependency.
- **Milestone 5 — OpenAPI** generate OpenAPI components from a schema.

Typing and OpenAPI are both *projections* of the schema — see [docs/design.md](docs/design.md).

## Development

```sh
bundle install
bundle exec rspec
```

## License

[MIT](LICENSE.txt)
