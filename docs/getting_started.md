# Getting started

Accord turns untrusted input into a canonical, typed, validated Ruby object from a single schema declaration.

## Install

```ruby
# Gemfile
gem "accord"
```

For Rails, load the opt-in integration (`require "accord/rails"`); the `money`/`iso_currency` types additionally need `gem "money"`. Neither is required for the core.

## Define a schema

A schema is a subclass of `Accord::Schema`. Each line declares a field: a name, a type, optional validators (as positional flags or a block), and options like `default:`.

```ruby
require "accord"

class CreateEmployee < Accord::Schema
  string   :name, :required
  currency :salary, :positive
  boolean  :active, default: true
  date     :hired_on
end
```

## Parse input

`parse` is **permissive**: it coerces loose input, applies defaults, and collects a structured error per problem — it never raises. The result is an instance of your schema.

```ruby
input = CreateEmployee.parse({ name: "Ada", salary: "$65,000.00", hired_on: "2026-01-15" })

input.valid?     # => true
input.name       # => "Ada"                (String)
input.salary     # => 0.65e5               (BigDecimal — coerced from "$65,000.00", never a Float)
input.active     # => true                 (defaulted)
input.hired_on   # => #<Date 2026-01-15>
input.to_h       # => { name: "Ada", salary: 0.65e5, active: true, hired_on: #<Date ...> }
```

Accessors return coerced values directly — no `.value` wrappers, no strings to re-parse.

## Handle errors

Invalid input still parses; the problems land in `errors` as structured `Accord::Error` objects. Every field is checked in one pass, so you get all the errors at once:

```ruby
input = CreateEmployee.parse({ salary: "-5" })

input.valid?                 # => false
input.errors.map(&:to_h)
# => [ { path: [:name],   field: :name,   code: :required },
#      { path: [:salary], field: :salary, code: :not_positive, validator: :positive, value: -5.0e0 } ]
```

Errors are **data, not strings** — `path`, `code`, `validator`, `value`, and validator metadata — so you render them however a client needs (see [errors.md](errors.md)).

Prefer an exception when input is bad? `parse!` raises `Accord::InvalidInput` (carrying the same errors) unless the result is valid:

```ruby
CreateEmployee.parse!({ salary: "-5" })   # => raises Accord::InvalidInput
```

## What a schema also gives you

The one declaration is the source of truth for more than parsing:

```ruby
CreateEmployee.openapi   # => an OpenAPI object schema (properties, required, validator constraints)
CreateEmployee.rbs       # => an RBS class with typed reader signatures
```

## Next

- **[Rails](rails.md)** — the main guide: controller macro, error rendering, filters, testing.
- **[Types](types.md)** — the full type system and canonicalization.
- **[Validation](validation.md)** — built-in and custom validators.
- **[Typing](typing.md)** — RBS/RBI for Sorbet and Steep.
- **[examples/](../examples/)** — runnable scripts.
