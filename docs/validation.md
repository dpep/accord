# Validation

Validation in Accord is **declarative**: rules are metadata on a field, not imperative code scattered through a controller. Validators are composable, introspectable, and produce **structured errors** — they never render or format.

## Declaring validators

Two equivalent ways to attach a validator, plus a block for the rest:

```ruby
class CreateEmployee < Accord::Schema
  # positional flags — no-arg validators as symbols after the name
  string :name, :required

  # a block — for validators that take arguments
  integer :age do
    between 18..120
  end

  # combine both
  currency :salary, :required, :positive do
    max 1_000_000
  end
end
```

## The lifecycle

Per field, in one pass, **never failing fast**:

> parse → canonicalize → run validators → collect errors → continue to the next field

The goal is to aggregate every input error in a single parse. A field that fails coercion skips its validators (there's no usable value to check); a field that's absent skips them too (that's what `required` is for).

## Built-in validators

| Validator | Applies to | Error `code` | Metadata | OpenAPI |
|---|---|---|---|---|
| `required` | any | `:required` | — | (adds to `required` list) |
| `positive` | numeric | `:not_positive` | — | — |
| `negative` | numeric | `:not_negative` | — | — |
| `non_zero` | numeric | `:zero` | — | — |
| `min n` | comparable | `:too_small` | `expected:` | `minimum` |
| `max n` | comparable | `:too_large` | `expected:` | `maximum` |
| `between r` | comparable | `:out_of_range` | `min:`, `max:` | `minimum`/`maximum` |
| `length r` | String/Array | `:invalid_length` | `min:`, `max:` | `minLength`/`maxLength` |
| `inclusion list` | any | `:not_included` | `allowed:` | `enum` |
| `exclusion list` | any | `:excluded` | `disallowed:` | — |
| `format re` | String | `:invalid_format` | `pattern:` | `pattern` |

Each violation becomes a structured `Accord::Error`:

```ruby
schema = Class.new(Accord::Schema) { integer(:discount) { min 0 } }
schema.parse(discount: "-5").errors.first.to_h
# => { path: [:discount], field: :discount, code: :too_small, validator: :min, value: -5, expected: 0 }
```

Because validators carry OpenAPI metadata, the same declaration documents the contract:

```ruby
schema = Class.new(Accord::Schema) { integer(:age) { between 18..120 } }
schema.fields[:age].openapi   # => { type: "integer", minimum: 18, maximum: 120 }
```

## Composition

Every validator on a field runs, so a value can produce several errors at once:

```ruby
schema = Class.new(Accord::Schema) { integer(:n) { min 18; non_zero } }
schema.parse(n: "0").errors.map(&:code)   # => [:too_small, :zero]
```

## Custom validators

### Inline

A one-off rule, deferred to run per value. The block receives the coerced value and reports via `error(:code)`; the name is optional (defaults to `:custom`):

```ruby
currency :salary do
  validate(:increment) { |v| error(:bad_increment) unless (v % 100).zero? }
end
```

The name tags the error's `validator`; the `code` comes from your `error(...)` call. (Why the block? It defers value-dependent logic to parse time — see the note in [../README.md](../README.md) if the two-block structure looks redundant.)

### Reusable classes

Subclass `Accord::Validators::Base` and implement `#validate(value, collector)`:

```ruby
class EvenValidator < Accord::Validators::Base
  def validate(value, collector)
    collector.add(:odd) unless value.even?
  end

  def openapi = { multipleOf: 2 }   # optional contribution
end

class Counter < Accord::Schema
  integer :count do
    validator EvenValidator
  end
end
```

## The registry

Validators live in a registry, so **built-ins and your own are added the same way** and usable by name in any field block:

```ruby
# a block-based validator, usable everywhere as `even`
Accord::Validators.register(:even) { |value, collector| collector.add(:odd) unless value.even? }

# or a class
Accord::Validators.register(:iban, IbanValidator)

class Account < Accord::Schema
  integer :count do
    even            # resolved through the registry
  end
end
```

Registry API: `register(name, klass_or_&block)`, `registered?(name)`, `build(name, *args)`, `names`, `clear`, `reset` (restores the built-ins). Register your app's standard validators once in an initializer.

## Nested validation

Nested schemas produce nested paths automatically — no special handling:

```ruby
class Address < Accord::Schema
  string :zip do
    format(/\A\d{5}\z/)
  end
end

class CreateEmployee < Accord::Schema
  object :address, Address
end

CreateEmployee.parse(address: { zip: "abc" }).errors.first.path   # => [:address, :zip]
```

## Introspection

Field metadata is queryable — the foundation for OpenAPI, docs, and (future) form/test/client generation:

```ruby
field = CreateEmployee.fields[:salary]
field.required?                       # => true / false
field.validators.map(&:name)          # => [:required, :positive, :max]
```

## Testing schemas

Schemas are plain Ruby, so test them directly — faster and clearer than going through a controller:

```ruby
RSpec.describe CreateEmployee do
  it "requires a positive salary" do
    input = described_class.parse(name: "Ada", salary: "-5")
    expect(input.errors.map(&:code)).to include(:not_positive)
  end

  it "coerces and accepts valid input" do
    input = described_class.parse(name: "Ada", salary: "$50,000")
    expect(input).to be_valid
    expect(input.salary).to eq(BigDecimal("50000"))
  end
end
```

---

See also: [errors.md](errors.md) · [rails.md](rails.md) · [types.md](types.md)
