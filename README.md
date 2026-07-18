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
| `boolean`  | `true`/`false`, `"true"`/`"false"`, `"1"`/`"0"`, `"yes"`/`"no"` | `true`/`false` | `true`/`false` |
| `date`     | Date, Time, ISO-8601, configured legacy `formats:` | Date, Time, ISO-8601 | `Date` |
| `currency` | `"10"`, `"10.50"`, `"$10.50"`, `"1,000.00"`, Integer, Float | plain numeric strings, Integer | `BigDecimal` |

Currency is always `BigDecimal`, never `Float` — Floats are rejected in strict mode and routed through their string form otherwise, so binary rounding never enters the pipeline.

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

## Errors

Errors are first-class objects (`Accord::Error`) carrying `field`, `path`, `code`, `message`, `input`, and `value`. Paths are arrays so nested schemas (coming next) can point at `[:employees, 2, :salary]`.

```ruby
input.errors.first.to_h
# => { field: :salary, path: [:salary], code: :invalid_currency,
#      message: "invalid_currency", input: "$abc", value: nil }
```

## Rails integration

Opt-in and decoupled — the core gem carries no Rails or ActiveSupport dependency. Load it with:

```ruby
gem "accord", require: "accord/rails"
```

This wires permissive-parse events to `ActiveSupport::Notifications` and makes `parse_input` available in controllers:

```ruby
class EmployeesController < ApplicationController
  def create
    input = parse_input(CreateEmployee)   # 422 with structured errors if invalid
    EmployeeService.call(input)
    head :created
  end
end
```

The schema *is* the allowlist (it reads only declared fields), so params are taken unfiltered. Invalid input raises `Accord::InvalidInput`, rendered as a 422 by a `rescue_from` installed on include.

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
- **Milestone 3 — Rails integration** ✅ controller helpers, `ActiveSupport::Notifications`, params handling.
- **Milestone 4 — OpenAPI** generate OpenAPI components from a schema.

## Development

```sh
bundle install
bundle exec rspec
```

## License

[MIT](LICENSE.txt)
