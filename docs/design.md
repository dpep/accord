# Accord — design notes

Executable API contracts for Ruby. **A schema is the source of truth for an API boundary**: it declares accepted input, coerces it, validates it, exposes a typed object, and documents the contract.

The internal object model (`Schema`, `Field`, `Type`, `Error`, paths) is the hard part and the foundation. Everything downstream — OpenAPI, typing, docs — is a **projection** of that model, not a second definition. When we know the types, we generate the downstream artifact rather than asking the user to restate it.

## Projections

Same generator pattern, different targets. The schema is the one definition; each projection reads it.

| Projection | Method | Consumer |
|---|---|---|
| Types | `Schema.rbs` | Sorbet / Steep / editors |
| Docs | `Schema.openapi` | OpenAPI / rswag |

Typing ships **before** OpenAPI: it improves every downstream developer experience (autocomplete, type-checking of `input.salary` as `BigDecimal`) and integrates cleanly with typed codebases, with no runtime dependency — we only emit signatures.

## Milestones

- **M1 — Core types** ✅ Schema, Field, typed input object, String/Boolean/Date/Currency, Error objects. No Rails.
- **M2 — Nested schemas** ✅ `object`/`array` fields, composed error paths (`[:employees, 2, :salary]`).
- **M3 — Rails integration** ✅ baseline (`ControllerHelpers`, `ActiveSupport::Notifications`, params handling).
  - **M3.1 — refinement** ✅ `Schema.parse!` entry point, declarative `accord` controller macro (lazy memoized reader, `from:` source scoping), `Accord.configure { |c| c.strict = ... }` default mode, overridable `render_accord_errors`.
- **M4 — Typing projection** `Schema.rbs` — generate RBS signatures for the parsed result. Field → Ruby type is already known (`string → String`, `currency → BigDecimal`, `boolean → bool`, `object → sub-schema`, `array → T::Array[sub]`).
- **M5 — OpenAPI** `Schema.openapi` — components with required fields, nested properties, array items, descriptions, examples; later rswag.

## Decisions

- **Schema is the entry point.** `Schema.parse` (permissive, collects errors) and a raise-on-invalid variant are the public API. Controller code talks to the schema, not to a wrapper.
- **Default parse mode is configurable.** `Accord.configure { |c| c.strict = false }` sets the default; per-call `strict:` always wins. Shipped default stays non-strict (an API boundary tolerates and reports; strict is the trusted-internal-caller mode).
- **Error rendering is an overridable method, not config.** The Rails concern ships a default `render_accord_errors(error)`; apps override the one method. Inherits naturally per-controller.
- **Declarative macro declares an input reader, not an action hook.** `accord :employee, CreateEmployee` defines a lazily-parsed, memoized reader — decoupled from action names, so a controller can declare several. Eager validation is opt-in via `before_action :employee`.
- **Typing/OpenAPI are generated projections, not definition surfaces.** We do not adopt `T::Struct` as a way to define input shapes — it can't coerce, parse permissively, or collect structured errors, and it would split the source of truth.

## Open questions (revisit)

- **Auto-rescue vs. caller-owned.** The concern currently installs `rescue_from(InvalidInput)` automatically. Question whether to keep that implicit or leave rescue to the caller with a clean documented example. Leaning: make the raise-and-render behavior easy but not silently global. _Left as-is for now._
- **i18n / translated errors.** Error messages should probably be translatable. Likely shape: an optional message-resolver hook (same pattern as `Accord.notifier`), with the Rails integration wiring `I18n.t("accord.errors.#{code}", **interpolation)` and falling back to the code. Keeps core i18n-free.
- **Action argument injection.** Whether actions may receive the parsed input as a parameter (`def create(employee)`). Possible by overriding `send_action`, but breaks the zero-arg action convention the ecosystem assumes. Leaning: keep the memoized reader as default.
- **Inflected reader names.** `accord CreateEmployee` could infer `employee` by inflection. Leaning explicit (`accord :employee, CreateEmployee`) for clarity; inflection is fragile and the saved keystrokes are few.
