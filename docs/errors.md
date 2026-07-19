# Errors

Accord errors are **structured data, not strings**. A validator's job ends at reporting *what* went wrong (`path`, `code`, metadata); turning that into a message — Rails JSON, GraphQL, i18n, a log line — is a separate concern the validator layer knows nothing about. This keeps one contract renderable into many formats.

## `Accord::Error`

Every problem is an `Accord::Error`:

| Attribute | Meaning |
|---|---|
| `path` | array locating the field, e.g. `[:employees, 2, :salary]` |
| `code` | the machine code, e.g. `:required`, `:not_positive`, `:invalid_currency` |
| `field` | the leaf field (defaults to the last path segment) |
| `validator` | the validator that reported it (validation failures only), e.g. `:min` |
| `value` | the coerced value that failed validation |
| `input` | the raw input that failed coercion (coercion failures only) |
| `metadata` | validator-specific keys, e.g. `expected:`, `min:`, `max:`, `pattern:` |

`#to_h` serializes to structured data, dropping nil keys — from the minimal machine form to the full validator error:

```ruby
# a coercion failure
{ path: [:salary], field: :salary, code: :invalid_currency, input: "$abc" }

# a validation failure
{ path: [:discount], field: :discount, code: :too_small, validator: :min, value: -5, expected: 0 }
```

There is deliberately **no `message`**. Rendering owns that.

## Nested paths

Nested schemas produce nested paths with no special handling — the object key, then the array index, then the leaf field:

```ruby
input.errors.map(&:path)
# => [[:employee, :salary], [:employees, 3, :salary], [:address, :zip]]
```

## Rendering

The same `errors` array renders into whatever a client expects.

### Machine-readable JSON

```ruby
render json: { errors: input.errors.map(&:to_h) }, status: :unprocessable_entity
```

### Rails-style `{ field => [messages] }`

Map codes to human text where the response is built (a natural place for i18n):

```ruby
MESSAGES = { required: "can't be blank", not_positive: "must be positive", too_small: "is too small" }.freeze

input.errors.group_by(&:field).transform_values do |errs|
  errs.map { |e| MESSAGES.fetch(e.code, e.code.to_s) }
end
# => { salary: ["must be positive"], name: ["can't be blank"] }
```

### GraphQL

The `path` array is already GraphQL's error path:

```ruby
input.errors.map do |e|
  { message: I18n.t("errors.#{e.code}", **e.metadata), path: e.path, extensions: { code: e.code } }
end
```

### i18n

`code` + `field` + `metadata` supply every interpolation a translation needs:

```yaml
# config/locales/en.yml
en:
  accord:
    errors:
      required: "%{field} is required"
      too_small: "%{field} must be at least %{expected}"
      out_of_range: "%{field} must be between %{min} and %{max}"
```

```ruby
I18n.t("accord.errors.#{e.code}", field: e.field, **e.metadata)
```

### Logs / metrics

Structured errors are log- and metric-friendly as-is (`e.to_h`), and permissive parses also emit them as events — see [Observability](#observability).

## Code reference

**Coercion codes** (a value couldn't become the canonical type):

| Code | When |
|---|---|
| `:required` | a required field is absent |
| `:invalid_<type>` | e.g. `:invalid_currency`, `:invalid_date`, `:invalid_uuid`, `:invalid_integer` |
| `:invalid_scale` | a decimal exceeded its `scale` (and `round:` is off) |
| `:invalid_object` | an `object`/`money` field got a non-hash |
| `:invalid_array` | an `array` field got a non-array |

**Validation codes** are listed per validator in [validation.md](validation.md#built-in-validators) (`:not_positive`, `:too_small`, `:out_of_range`, `:invalid_length`, `:not_included`, `:invalid_format`, …), plus any codes your custom validators report.

## Observability

In permissive mode, every error Accord tolerates emits an `ActiveSupport::Notifications` event named `accord.parse.<code>` (wired by `accord/rails`). Subscribe to measure malformed-input rates or watch an API migration:

```ruby
ActiveSupport::Notifications.subscribe(/accord\.parse/) do |name, _s, _f, _id, payload|
  # name    => "accord.parse.invalid_currency"
  # payload => { field: :salary, path: [:salary], validator: :positive, value: ... }
  StatsD.increment(name, tags: { field: payload[:field] })
end
```

---

See also: [validation.md](validation.md) · [rails.md](rails.md#rendering-errors)
