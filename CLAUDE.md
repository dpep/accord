# Accord

Executable API contracts for Ruby. A schema is the source of truth for an API boundary: it declares accepted input, coerces it, validates it, exposes a typed object, and documents the contract.

## Core principles

**The schema is the single source of truth for an API boundary.** Everything derives from the schema definition — parsing, coercion, validation, canonicalization, error reporting, OpenAPI, typing (RBS/RBI), documentation, and (later) test/client generation. Never duplicate contract information across systems. **Always favor declarative metadata over imperative logic**: if a feature can be expressed as schema metadata (a type, a validator, an option), prefer that — it keeps parsing, validation, docs, OpenAPI, and tooling in sync.

**Canonical representations.** Accord parses external representations into canonical internal values, and `dump` always emits canonical external representations. Equivalent inputs must produce identical outputs (`TRUE`/`True` → `true`; `$1,234.50` → `BigDecimal("1234.50")`; `550E8400-...` → `550e8400-...`). Canonicalization is a fundamental responsibility of every type. Every type implements the same interface: `parse` (permissive), `parse!` (strict), `dump` (canonical external), `openapi`, `rbs`/`sorbet`, `graphql`.

**Validators are declarative.** Validation rules belong to schemas (field blocks) and are reusable, composable, and introspectable. A validator only produces structured violations — it never renders, formats, or generates human-readable messages.

**Errors are structured data, not strings.** Every `Accord::Error` carries `path`, `code`, `validator`, `value`, and validator-specific metadata (`expected`, `min`, `max`, …) — no message. Rendering (Rails JSON, GraphQL, i18n, logs) is a separate concern the validator layer knows nothing about. Nested schemas naturally produce nested paths (`[:employees, 3, :salary]`) with no special handling.

## Type system

A small set of primitives — `String`, `Boolean`, `Date`, `Decimal` — plus **semantic specializations** that add parsing rules, canonicalization, defaults, and OpenAPI metadata without introducing new internal representations. **Composite** types (e.g. `Money`) compose scalars via a field, not a new primitive:

```
String              Decimal            Composite
├── UUID            ├── Currency       └── Money  (Decimal amount + ISOCurrency)
└── ISOCurrency     └── Duration
```

Keep the primitive set very small (`String`, `Boolean`, `Integer`, `Decimal`, `Date`, `DateTime`). Everything else is a **semantic scalar type** (UUID, Duration, Percentage, Currency, Email, URL, ISOCurrency — adds meaning/parsing/canonicalization/validation/OpenAPI over a primitive's storage) or a **reusable schema/composite** (Money, Address, Employee — composes existing types, introduces no new primitive).

When adding a domain type, specialize the nearest primitive rather than inventing a new internal representation. `Decimal` (scale enforcement, BigDecimal, `dump` projection) is the reference for semantic decimal types; `UUID` is the reference for semantic string types (override `String#canonicalize`); `Money` (a `MoneyField` composing scalar fields, with naturally-nesting error paths and no special cases) is the reference for composite types.

## Validation lifecycle

Per field, in one pass, never fail fast: **parse → canonicalize → run validators → collect errors → continue to the next field.** The goal is to aggregate every input error in a single parse. Validation is declared in field blocks:

```ruby
currency :salary do
  positive
  validate(:increment) { |v| error(:bad_increment) unless (v % 100).zero? }  # custom inline
end
```

Built-in validators live in `Accord::Validators`; each reports `code` + metadata and may contribute OpenAPI (`between 0..100` → `minimum`/`maximum`, `length 1..50` → `minLength`/`maxLength`, `inclusion [...]` → `enum`). Custom validators are inline blocks or reusable `Validators::Base` subclasses. Field validator metadata is introspectable (`Schema.fields[:x].validators`) and is designed to power OpenAPI, docs, form/test/client generation.

## Conventions

- Never use `Float` for money/precision — `BigDecimal` internally, always.
- Strict mode raises on the first coercion failure (trusted callers); non-strict collects structured `Accord::Error`s and emits `accord.parse.<code>` via `Accord.notifier`. Strict affects coercion only — validations always collect.
- Rounding is never silent — `decimal`/`currency`/`duration` reject excess precision unless `round: true`.
- Keep the core gem free of Rails/ActiveSupport; Rails integration is opt-in (`require "accord/rails"`). The `money` gem is an optional dependency — `money` and `iso_currency` lazy-require it (`Accord.require_money!`) with a clear error if absent.
- Tests: quality over quantity — accepted inputs, rejected inputs, strict vs. permissive, `dump`, and OpenAPI per type.
- Configure at boot. `Accord.config`, the validator registry, and schema definitions are global mutable state initialized lazily (`@x ||=`) — set them in initializers, not concurrently at runtime.
- Permissive parse never raises — it collects. A type's permissive `coerce` must route bad input through `invalid!` (never let an exception escape); guard edge cases like non-finite Floats.

See [docs/design.md](docs/design.md) for milestones and open questions.
