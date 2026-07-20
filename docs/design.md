# Accord — design notes

Executable API contracts for Ruby. **A schema is the source of truth for an API boundary**: it declares accepted input, coerces it, validates it, exposes a typed object, and documents the contract.

The internal object model (`Schema`, `Field`, `Type`, `Error`, paths) is the hard part and the foundation. Everything downstream — OpenAPI, typing, docs — is a **projection** of that model, not a second definition. When we know the types, we generate the downstream artifact rather than asking the user to restate it.

## Projections

Same generator pattern, different targets. The schema is the one definition; each projection reads it.

| Projection | Method | Consumer |
|---|---|---|
| Types (RBS) | `Schema.rbs` | Steep / editors |
| Types (RBI) | `Schema.rbi` + Tapioca compilers | Sorbet |
| Docs | `Schema.openapi` / `Accord::ControllerHelpers.openapi_document` | OpenAPI / rswag |
| GraphQL | `Schema.graphql` | GraphQL input-type SDL |

Typing ships **before** OpenAPI: it improves every downstream developer experience (autocomplete, type-checking of `input.salary` as `BigDecimal`) and integrates cleanly with typed codebases, with no runtime dependency — we only emit signatures.

## Milestones

- **M1 — Core types** ✅ Schema, Field, typed input object, String/Boolean/Date/Currency, Error objects. No Rails.
- **M2 — Nested schemas** ✅ `object`/`array` fields, composed error paths (`[:employees, 2, :salary]`).
- **M3 — Rails integration** ✅ baseline (`ControllerHelpers`, `ActiveSupport::Notifications`, params handling).
  - **M3.1 — refinement** ✅ `Schema.parse!` entry point, declarative `accord` controller macro (lazy memoized reader, `from:` source scoping), `Accord.configure { |c| c.strict = ... }` default mode, overridable `render_accord_errors`.
- **M4 — Typing projection** ✅ `Schema.rbs` — generates RBS signatures for the parsed result. Each type/field declares its RBS type (`String`, `BigDecimal`, `bool`, `Date`, nested schema name, `Array[...]`, `Money`); the schema assembles typed reader signatures (required/defaulted → non-nilable, optional → nilable).
- **M5 — OpenAPI** ✅ `Schema.openapi` (object schema: properties + `required` + validator-derived constraints, nested schemas by `$ref`) and `Schema.openapi_schemas` / `Accord.openapi_schemas` (components map). Feeds rswag's `components.schemas`; paths stay the app's/rswag's job. See docs/openapi.md.
- **M6 — Declarative validation** ✅ Field-block validator DSL (`currency :salary do positive end`), built-in validators (required/min/max/between/positive/negative/non_zero/length/inclusion/exclusion/format), custom inline + reusable validator classes. Structured errors (path/code/validator/value/metadata, no message). Lifecycle: parse → canonicalize → validate → collect → continue (never fail fast). Validators contribute OpenAPI and are introspectable. Added `Integer` (primitive) and `Percentage` (semantic Decimal). Dropped the old top-level `validate`. Rendering is a separate concern.

## Beyond the core (shipped)

The M1–M6 foundation held; the work since has been projections, tooling, and hardening on top of it — no changes to the object model's shape.

- **More projections** — `Schema.rbi` + bundled Tapioca DSL compilers (schema readers, `parse!` as `T.attached_class`, and controller readers from `accord`/`accepts`); `Schema.graphql` (GraphQL input SDL).
- **Type/DSL ergonomics** — a `Types` registry (override built-ins, add semantic types) that generates the schema DSL; keyword-validator shorthand (`string :name, format: /re/`); scalar arrays (`array :tags, :string`); more semantic types (UUID versioned, Email, URL, IPAddress, ISOCurrency, DateTime).
- **i18n** — shipped `Accord::Messages` (ActiveModel-style) + a locale, resolving the M6 open question. Rendering stays a separate concern.
- **Contract DSL** — the `accepts`/`returns` per-action decorators, an `Accord::Endpoint` registry, and `openapi_document` — full-document generation (paths + components + a shared `AccordErrors` response) from the same declarations. `accord` remains as the simpler named-reader tool.
- **Correctness & posture** — client-fault (4xx, collect) vs. programmer-fault (5xx, fail fast at boot) distinction; declaration-time validator applicability; coerced/validated defaults; explicit-null-vs-absent PATCH semantics (`to_h(compact:)`); universal whitespace strip; registry `freeze!`.
- **Adoption** — a strangler-fig [migration guide](migration.md), an inventory task, and opt-in `require "accord/rspec"` matchers (`conform_to`, `have_error`).

## Decisions

- **Schema is the entry point.** `Schema.parse` (permissive, collects errors) and a raise-on-invalid variant are the public API. Controller code talks to the schema, not to a wrapper.
- **Default parse mode is configurable.** `Accord.configure { |c| c.strict = false }` sets the default; per-call `strict:` always wins. Shipped default stays non-strict (an API boundary tolerates and reports; strict is the trusted-internal-caller mode).
- **Error rendering is an overridable method, not config.** The Rails concern ships a default `render_accord_errors(error)`; apps override the one method. Inherits naturally per-controller.
- **Declarative macro declares an input reader, not an action hook.** `accord :employee, CreateEmployee` defines a lazily-parsed, memoized reader — decoupled from action names, so a controller can declare several. Eager validation is opt-in via `before_action :employee`.
- **Typing/OpenAPI are generated projections, not definition surfaces.** We do not adopt `T::Struct` as a way to define input shapes — it can't coerce, parse permissively, or collect structured errors, and it would split the source of truth.

## Open questions (revisit)

- **Auto-rescue vs. caller-owned.** The concern installs `rescue_from(InvalidInput)` (and strict `CoercionError`/`MissingField`) automatically. Whether to keep that implicit or leave rescue to the caller. _Left as-is; it's the ergonomic default and overridable._
- **Single-controller API versioning.** Multiple `accepts` on one action, resolved by request version (`accepts V1::Create, version: 1`), vs. namespaced controllers per version. Namespaced controllers work today and generate per-version docs cleanly; the resolver approach is a possible add.
- **GraphQL SDL's home.** The projection is the most speculative surface (graphql-ruby defines types in Ruby, not SDL). Whether to keep it in core (consistent with the other projections, ~50 lines), extract to opt-in `require "accord/graphql"`, or remove if unused. _Leaning: keep, revisit with usage data._
- **Response-mode OpenAPI.** A response `Schema` (via `dump!`) projects with request-shaped `required`; a `Schema.openapi(mode: :response)` (all-present, optionals nullable) may be worth it if the default proves loose.

_Resolved since:_ i18n (shipped `Accord::Messages` + locale); inflected reader names (explicit wins — `accord :employee, S`; `accepts` defaults to `input` with `as:`/config override); typing-before-OpenAPI sequencing (both shipped).
