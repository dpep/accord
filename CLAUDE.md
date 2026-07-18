# Accord

Executable API contracts for Ruby. A schema is the source of truth for an API boundary: it declares accepted input, coerces it, validates it, exposes a typed object, and documents the contract.

## Core design principle

**Accord parses external representations into canonical internal values, and `dump` always emits canonical external representations.** Equivalent inputs must produce identical outputs (`TRUE`/`True` → `true`; `$1,234.50` → `BigDecimal("1234.50")`; `550E8400-...` → `550e8400-...`).

The aim is simplicity of use with consistent, clear types on the way in and the way out. Every type implements the same interface: `parse` (permissive), `parse!` (strict), `dump` (canonical external), `openapi` (documentation projection).

## Type system

A small set of primitives — `String`, `Boolean`, `Date`, `Decimal` — plus **semantic specializations** that add parsing rules, canonicalization, defaults, and OpenAPI metadata without introducing new internal representations:

```
String              Decimal
├── UUID            ├── Currency
                    └── Duration
```

When adding a domain type, specialize the nearest primitive rather than inventing a new internal representation. `Decimal` (scale enforcement, BigDecimal, `dump` projection) is the reference for semantic decimal types; `UUID` is the reference for semantic string types (override `String#canonicalize`).

## Conventions

- Never use `Float` for money/precision — `BigDecimal` internally, always.
- Strict mode raises on the first coercion failure (trusted callers); non-strict collects structured `Accord::Error`s and emits `accord.parse.<code>` via `Accord.notifier`. Strict affects coercion only — validations always collect.
- Rounding is never silent — `decimal`/`currency`/`duration` reject excess precision unless `round: true`.
- Keep the core gem free of Rails/ActiveSupport; Rails integration is opt-in (`require "accord/rails"`).
- Tests: quality over quantity — accepted inputs, rejected inputs, strict vs. permissive, `dump`, and OpenAPI per type.

See [docs/design.md](docs/design.md) for milestones and open questions.
