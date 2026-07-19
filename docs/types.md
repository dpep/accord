# Types

Accord keeps a **small primitive set** and builds everything else as a semantic specialization or a composite — so the type system stays small while domain types stay expressive. Every type parses an external representation into a **canonical internal value** and dumps back to a canonical external one; equivalent inputs always produce identical outputs.

## The type interface

Every type implements the same four methods:

| Method | Purpose |
|---|---|
| `parse(value)` | permissive coercion — returns the canonical value, or `nil` (logged) on bad input |
| `parse!(value)` | strict coercion — returns the value or raises `Accord::CoercionError` |
| `dump(value)` | the canonical **external** representation (e.g. a decimal string) |
| `openapi` / `rbs` / `sorbet` | documentation and typing projections |

Inside a schema, permissive parsing collects a structured error instead of returning `nil`; strict parsing raises. See [Rails](rails.md#strict-mode) for how modes surface at the boundary.

## The field DSL

| DSL | Internal value | Notes |
|---|---|---|
| `string :name` | `String` | permissive also coerces Symbol/Numeric via `to_s` |
| `uuid :id` | `String` | canonical **lowercase** RFC 4122 (`550E8400-…` → `550e8400-…`) |
| `iso_currency :currency` | `String` | canonical **uppercase** ISO-4217 (`usd` → `USD`); needs `money` |
| `boolean :active` | `true`/`false` | permissive accepts `"true"`/`"1"`/`"yes"` etc. |
| `integer :age` | `Integer` | permissive accepts integer strings and whole Floats |
| `date :on` | `Date` | ISO-8601 + configurable legacy `formats:` |
| `decimal :rate, scale: 4` | `BigDecimal` | configurable precision |
| `currency :salary` | `BigDecimal` | `Decimal` with default `scale: 2`, strips `$`/`,` |
| `duration :hrs, unit: :hours` | `BigDecimal` | `Decimal` labeled with a time unit |
| `percentage :discount` | `BigDecimal` | `Decimal`, default `scale: 2` |
| `object :address, Address` | schema instance | nested schema |
| `array :items, LineItem` | `Array` of instances | nested schemas, indexed error paths |
| `money :salary` | `Money` (gem) | amount + currency composite; needs `money` |

## Canonicalization

Canonicalization is a fundamental responsibility of every type — the reason equivalent inputs round-trip identically:

```text
"TRUE" / "True"                       -> true
"$1,234.50"                           -> BigDecimal("1234.50")
"550E8400-E29B-41D4-A716-446655440000"-> "550e8400-e29b-41d4-a716-446655440000"
"usd"                                 -> "USD"
```

`dump` reverses it to the canonical external form. A type carries config (a `Currency`'s `scale`, a `Date`'s `formats`) and is reused across values, so `dump` takes the value — `type.dump(value)`. For the no-config case there are class-method delegators (over a default-config instance):

```ruby
Accord::Types::UUID.dump("550E8400-...")            # => "550e8400-..."
Accord::Types::Currency.dump(BigDecimal("1000.5"))  # => "1000.50"  (default scale 2)

# with non-default config, use an instance:
Accord::Types::Currency.new(scale: 4).dump(BigDecimal("1.5"))  # => "1.5000"
```

Inside a schema you rarely call this directly — projections (`dump`, `openapi`) use it for you.

## Decimals: scale and rounding

`decimal`, `currency`, `duration`, and `percentage` are all `BigDecimal` internally — **never `Float`** (Floats are rejected in strict mode and routed through their string form otherwise, so binary rounding never enters the pipeline).

`scale:` is the number of decimal places, **enforced on parse**. Excess precision is rejected (`code: :invalid_scale`) rather than silently rounded — unless you opt in with `round: true`:

```ruby
class Order < Accord::Schema
  decimal  :rate, scale: 4               # "0.12345" -> :invalid_scale error
  currency :total                        # scale 2
  currency :fee, :positive, round: true  # "1.999" -> BigDecimal("2.00")
end
```

`dump` always renders exactly `scale` places: `dump(BigDecimal("12")) # => "12.00"`.

## Money

`money` is a **composite**, not a new primitive: it composes a `Decimal` amount and an `ISOCurrency`, parsing the nested wire form into a [`money`](https://rubygems.org/gems/money)-gem `Money` value. Requires `gem "money"`.

```ruby
class Payroll < Accord::Schema
  money :salary                        # nested { amount:, currency: }
  money :bonus,   format: :flat        # sibling keys: bonus + bonus_currency
  money :stipend, currency: "USD"      # fixed currency (input ignored)
  money :fee,     default_currency: "USD"  # currency optional, defaults to USD, input overrides
end

Payroll.parse(salary: { amount: "1234.50", currency: "usd" }).salary
# => #<Money fractional:123450 currency:USD>
```

Because money composes ordinary fields, its errors nest with no special handling — `[:salary, :amount]`, `[:salary, :currency]`. The amount's precision is **currency-aware** (validated against the currency's subunit exponent: USD → 2, JPY → 0, BHD → 3), and `dump` always emits the canonical nested `{ amount:, currency: }` form regardless of input format.

A **default currency** — per-field `default_currency:` or global `Accord.config.default_currency` — makes money polymorphic: a bare amount takes the default, an explicit currency overrides. `currency:` instead locks it.

## Custom semantic types

Add a domain type by specializing the nearest primitive rather than inventing a new internal representation:

- **Semantic string** — subclass `Accord::Types::String` and override `#canonicalize(string, strict:)` to normalize + validate (this is exactly how `UUID` and `ISOCurrency` work).
- **Semantic decimal** — subclass `Accord::Types::Decimal` for defaults + metadata (like `Currency`, `Duration`, `Percentage`).
- **Composite** — a `Field` subclass that composes scalar fields (like `MoneyField`).

```ruby
module Accord
  module Types
    class Slug < String
      PATTERN = /\A[a-z0-9-]+\z/
      private def canonicalize(string, strict:)
        normalized = string.strip.downcase
        invalid!(string) unless normalized.match?(PATTERN)
        normalized
      end
    end
  end
end

# register a DSL method
class Accord::Schema
  def self.slug(name, *flags, **opts, &block)
    field(name, Types::Slug.new, *flags, **opts, &block)
  end
end
```

---

See also: [validation.md](validation.md) · [errors.md](errors.md) · [typing.md](typing.md)
