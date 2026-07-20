# Migrating an existing Rails app to Accord

Adopting Accord in a large app — hundreds of controllers on `params.require/permit`, validations scattered across models, jbuilder/AMS/RABL serializers — is a strangler-fig migration, not a rewrite. Schemas take over one boundary at a time, and the observability built into permissive parsing (`accord.parse.*` events) turns "is it safe to switch?" from a guess into a measurement.

This guide is the migration playbook: sequencing, coexistence, shadow mode, seeding schemas from what you have, tightening, and the behavioral differences to watch for.

- [Principles and sequencing](#principles-and-sequencing)
- [Coexistence](#coexistence)
- [Shadow mode](#shadow-mode)
- [Seeding schemas from what exists](#seeding-schemas-from-what-exists)
- [Tightening safely](#tightening-safely)
- [Behavioral differences to watch](#behavioral-differences-to-watch)
- [Tooling and rollout](#tooling-and-rollout)

---

## Principles and sequencing

**Migrate the input side; leave the output side alone.** Accord replaces `permit`, hand-written coercion, and input-shape validation. Your jbuilder/AMS/RABL serializers render *results*, not input — they are untouched by this migration (see [integrations.md](integrations.md#rabl)). Don't couple the two: an endpoint is "migrated" when its input flows through a schema, regardless of how it renders.

**One endpoint at a time, always shippable.** Every intermediate state — some controllers on Accord, most not — is a stable, deployable state. `require "accord/rails"` includes the concern app-wide, but the macro and `rescue_from` are inert until a controller actually declares an input.

**Where to start:**

1. **New endpoints, immediately.** Zero migration risk, and it stops the backlog growing. Make "new endpoints use `accord`" the team convention on day one.
2. **A pilot cohort: medium-traffic, well-understood endpoints.** Not your riskiest endpoint first — you want reps with the workflow (seeding, shadow, flip) before touching the money path. Prefer endpoints whose clients you control, so a behavioral difference is cheap to fix.
3. **High-traffic endpoints once the workflow is proven.** These benefit most from shadow mode: heavy traffic means `accord.parse.*` events map the real input variants fast.
4. **Long-tail cleanup by controller cohort** (admin, internal API, v1, ...), tracked with the [inventory task](#tooling-and-rollout).

**"Done" per endpoint** means:

- The action reads input only through the `accord` reader (or `Schema.parse!`) — no `params[...]` access, no `permit` helper left.
- The old `xxx_params` method is deleted (grep for other callers first).
- The 422 shape is deliberate — either the new structured shape or a legacy-compatible one via `render_accord_errors` ([Coexistence](#error-responses)).
- Request specs cover: a valid request, a coercion failure, a validation failure, and (for PATCH) partial-update semantics.
- The schema lives in `app/schemas` with its own spec, or inline in the controller if single-use.
- Shadow/`observe_coercions` events for the endpoint are quiet, or the noisy fields are consciously left permissive.

---

## Coexistence

An Accord-migrated controller sits comfortably in an app where every other controller still uses strong parameters. The layers to think about, in the order you replace them:

### 1. Strong parameters — replace first

The schema *is* the allowlist: it reads only its declared fields via `[]`/`key?`, which `ActionController::Parameters` allows without `permit` ([rails.md](rails.md#strong-parameters)). Swapping `permit` for a schema is the core move, endpoint by endpoint:

```ruby
class EmployeesController < ApplicationController
  accord :employee, CreateEmployee, from: :employee   # mirrors params.require(:employee)

  def create
    record = Employee.create!(employee.to_h)
    render "employees/show", status: :created         # jbuilder view — unchanged
  end

  # deleted:
  # def employee_params
  #   params.require(:employee).permit(:name, :email, :salary, :active)
  # end
end
```

Match `from:` to whatever the old `require` scoped — `params.require(:employee)` becomes `from: :employee`. If your clients rely on `wrap_parameters` wrapping the JSON body, that keeps working the same way. Note one status-code change: `params.require(:employee)` raised `ParameterMissing` (a 400); with Accord, a missing root key parses as an empty hash and surfaces as `required` errors (a 422). Decide whether your clients care before flipping.

### 2. Model validations — keep, then dedupe carefully

Model validations protect *every* write path — admin controllers, jobs, consoles, other services — while a schema protects one controller boundary. So during migration, **change nothing on the model**. Duplication (schema `:required` + model `presence: true`) is temporarily fine: the schema catches it first with a 422, and the model check becomes a dormant backstop.

Dedupe later, and only what is genuinely *input shape*:

- **Move to the schema eventually:** format/length/inclusion/numericality checks that exist only to police API input.
- **Keep in the model forever:** uniqueness, cross-record checks, anything reading the DB or app state. Accord validators are pure functions of the input; stateful invariants aren't its job.
- **When unsure, keep both.** Removing a model validation is a separate, deliberate PR — audit every write path first.

### 3. Error responses

The default 422 body is `{ errors: [ { path:, code:, ... } ] }` — a breaking change for clients parsing the old ActiveModel shape. Preserve the legacy shape during migration by overriding one method in `ApplicationController` (see [rails.md](rails.md#rendering-errors)):

```ruby
class ApplicationController < ActionController::Base
  private

  # Legacy-compatible: { "errors": { "salary": ["must be positive"] } }
  def render_accord_errors(error)
    render json: { errors: Accord::Messages.messages(error.errors) }, status: :unprocessable_entity
  end
end
```

`Accord::Messages` mirrors `ActiveModel::Errors` (`messages`, `full_messages` — [errors.md](errors.md#i18n)), so most legacy shapes are reproducible. Exact message *text* may still differ from your model validations' — override the `accord.errors.<code>` locale keys where clients string-match (they shouldn't, but in a large app someone does).

### 4. Serializers — last, or never

jbuilder/AMS/RABL render domain objects and are orthogonal to input parsing. The only serialization Accord owns is echoing the *input* back canonically (`input.dump` — [integrations.md](integrations.md#rabl)). Leave response migration out of scope; if you later want response contracts, that's a separate project.

---

## Shadow mode

The strangler-fig core: run the schema **in parallel** with the existing code path, observe what it *would* have done, change nothing about behavior. Permissive `parse` never raises on bad field input — it collects errors — which makes it safe to run against live traffic.

Note the macro is *not* the shadow tool: its reader calls `parse!`, which raises `Accord::InvalidInput` and renders a 422 ([`controller_helpers.rb:145`](../lib/accord/controller_helpers.rb)). Shadow mode calls `Schema.parse` directly.

### The shadow helper

```ruby
# app/controllers/concerns/accord_shadow.rb
module AccordShadow
  # Parse permissively alongside the legacy path. Never raises, never renders —
  # only emits accord.parse.* events and logs divergence from the legacy path.
  def accord_shadow(schema, source = params, permitted: nil)
    input = schema.parse(source)   # permissive: collects errors, never raises on bad fields

    unless input.valid?
      Rails.logger.info(
        "[accord.shadow] #{schema.name} #{controller_path}##{action_name} invalid: " \
        "#{input.errors.map { |e| "#{e.path.join(".")}:#{e.code}" }.join(" ")}"
      )
    end

    if permitted
      extra = permitted.to_h.keys.map(&:to_sym) - schema.fields.keys
      Rails.logger.info("[accord.shadow] #{schema.name} permitted-but-undeclared: #{extra.inspect}") if extra.any?
    end

    input
  rescue StandardError => e
    # parse raises ArgumentError on a non-hash root; a shadow must never take
    # down the real request for any reason.
    Rails.logger.warn("[accord.shadow] #{schema.name} raised #{e.class}: #{e.message}")
    nil
  end
end
```

### In the controller

The legacy path is byte-for-byte unchanged; the shadow observes:

```ruby
class EmployeesController < ApplicationController
  include AccordShadow

  def create
    accord_shadow(CreateEmployee, params[:employee], permitted: employee_params)

    employee = Employee.new(employee_params)      # legacy path, untouched
    if employee.save
      render "employees/show", status: :created
    else
      render json: { errors: employee.errors }, status: :unprocessable_entity
    end
  end

  private

  def employee_params
    params.require(:employee).permit(:name, :email, :salary, :active)
  end
end
```

### Subscribe to the events

Permissive parsing emits an `ActiveSupport::Notifications` event per tolerated error (`accord.parse.<code>`, on by default), and — the key migration signal — `accord.parse.coerced` whenever input parsed only because permissive rules accepted what strict rules would reject (`"$1,000.00"`, `"yes"`, a legacy date format). The latter is opt-in ([`configuration.rb`](../lib/accord/configuration.rb)):

```ruby
# config/initializers/accord.rb
Accord.configure do |c|
  c.observe_coercions = true   # emit accord.parse.coerced — the permissive->strict signal
end

ActiveSupport::Notifications.subscribe(/\Aaccord\.parse/) do |name, _start, _finish, _id, payload|
  # name    => "accord.parse.invalid_currency" | "accord.parse.coerced" | ...
  # payload => { field: :salary, path: [:salary], ... }
  #            coerced events add input: (the raw variant) and value: (what it became)
  StatsD.increment(name, tags: { field: payload[:field] })
  Rails.logger.info("[accord] #{name} #{payload[:path].join(".")} <- #{payload[:input].inspect}") if payload.key?(:input)
end
```

`observe_coercions` costs a strict re-check per loose field and only runs when a notifier is listening ([`accord.rb`](../lib/accord.rb) `observe_coercions?`) — a migration tool you switch on, not steady-state overhead.

### What the shadow tells you

Three divergence classes, each with a distinct signal:

| Signal | Meaning | Action before flipping |
|---|---|---|
| `[accord.shadow] ... invalid` on requests the legacy path served fine | The schema is stricter than reality — a missed optional field, a validator the old path didn't have, a coercion the old code tolerated | Loosen the schema, or accept that these requests *should* have been 422s and coordinate with clients |
| `permitted-but-undeclared` keys | The `permit` list accepts fields the schema doesn't know about | Add the field, or confirm it's dead and let it drop |
| `accord.parse.coerced` events | Fields relying on permissiveness — fine to flip permissively, not yet ready for `strict:` | Nothing yet; this feeds [tightening](#tightening-safely) later |

**Flip when quiet.** After the shadow runs clean for a representative window (a week of traffic including whatever weekly/monthly clients you have), replace the legacy path with the macro, delete the shadow call and the `permit` helper, and move on. Keep the shadow phase short per endpoint — it's a verification window, not a permanent state.

---

## Seeding schemas from what exists

You have three sources of truth to mine — the `permit` list, the model's columns, and its validations — and none of them is sufficient alone. Be clear-eyed about what's mechanical and what's judgment.

**Mechanical (a script can draft it):**

- The `permit` list gives you the field *names* — but no types; strong params never had them.
- `Model.columns_hash` gives you plausible *types* for fields that mirror columns: `:string`/`:text` → `string`, `:boolean` → `boolean`, `:integer` → `integer`, `:decimal` → `decimal`, `:date` → `date`, `:datetime` → `datetime`, `:uuid` → `uuid`.
- Some validations translate directly: `presence: true` → `:required` · `numericality: { greater_than: 0 }` → `positive` · `inclusion: { in: [...] }` → `inclusion [...]` · `length: { maximum: 50 }` → `length 1..50` · `format: { with: /.../ }` → `format(/.../)`.

**Judgment (a human decides):**

- **Semantic types.** A `string` column holding emails should be `email`; a `decimal` holding dollars should be `currency`; an ID column might be `uuid`. The column type can't tell you — the domain does. This is also where migration pays off, so don't skip it.
- **API shape ≠ table shape.** Permitted params that aren't columns (virtual attributes, nested `*_attributes`), columns that must never be input (`id`, timestamps, counters, foreign keys set by context) — the schema describes the *contract*, not the table.
- **Defaults.** A DB default fires at insert; a schema `default:` fires at parse and shows up in `to_h`. Only lift a DB default into the schema if it's genuinely part of the API contract ("`active` defaults to true if omitted"), not a storage detail.
- **`presence` vs `:required`.** Not the same — `:required` rejects absent/null but accepts `""` (see [Behavioral differences](#behavioral-differences-to-watch)). Text fields that must be non-blank want `:required` *plus* a `length 1..` — or lean on the model validation you're keeping anyway.
- **Custom `validate` methods.** Pure-input ones become inline `validate` blocks; anything touching the DB stays in the model.

### A draft generator

A one-file rake task gets you a *draft* to edit — columns and translatable validations, nothing more. Don't expect it to produce a finished contract:

```ruby
# lib/tasks/accord_draft.rake
namespace :accord do
  desc "Print a draft Accord schema from a model (MODEL=Employee)"
  task draft: :environment do
    model = ENV.fetch("MODEL").constantize
    types = { string: :string, text: :string, boolean: :boolean, integer: :integer,
              decimal: :decimal, float: :decimal, date: :date, datetime: :datetime, uuid: :uuid }
    skip = %w[id created_at updated_at]

    puts "# draft — review every line: semantic types, defaults, API-only fields"
    puts "class #{model.name}Input < Accord::Schema"
    model.columns.reject { |c| skip.include?(c.name) }.each do |column|
      required = model.validators_on(column.name).any? { |v| v.kind == :presence }
      puts "  #{types.fetch(column.type, :string)} :#{column.name}#{", :required" if required}"
    end
    puts "end"
  end
end
```

Run it, paste the output into `app/schemas/`, and edit against the `permit` list (drop non-input columns, add virtual params, upgrade to semantic types, port the remaining validations). Budget the editing time — the draft is maybe half the work, and it's the easy half.

---

## Tightening safely

Permissive parsing is the migration posture, not necessarily the destination. Tighten in this order:

1. **Permissive + shadow** — observing only ([Shadow mode](#shadow-mode)).
2. **Permissive + enforcing** — the macro is live; loose input (`"$1,000"`, `"yes"`) still coerces, invalid input 422s. Most endpoints can happily stay here forever — a public boundary that tolerates and reports is a feature.
3. **Strict** — reject loose input on the first coercion failure. Only for boundaries where you control the clients and want canonical input on the wire.

The gate between 2 and 3 is data: with `observe_coercions` on, `accord.parse.coerced` tells you exactly which fields still *depend* on permissiveness and which raw variants they receive (the `input:` in the payload). The workflow from [rails.md](rails.md#from-permissive-to-strict): watch, group by field and variant, fix the offending clients at the source, and flip when the events go quiet. If some fields settle before others, split the settled ones into a strict sub-schema and keep the rest permissive.

Flipping is per-call or global:

```ruby
CreateEmployee.parse!(params, strict: true)          # this boundary only
Accord.configure { |c| c.strict = true }             # app-wide default; per-call strict: still wins
```

The `accord` macro takes a per-endpoint `strict:` (`accord :employee, CreateEmployee, strict: true`), so a strict boundary doesn't force you off the macro — loose or missing input still renders a 422. In a gradual migration, prefer per-endpoint `strict:` for a long time; the global flip (`Accord.config.strict = true`) is the *last* step, once every boundary is either strict-clean or deliberately split.

**Lock it down at boot.** Once the initializer reflects your final configuration, freeze it — a stray runtime mutation raises instead of racing ([`accord.rb`](../lib/accord.rb) `freeze!`):

```ruby
# config/initializers/accord.rb
Accord.configure do |c|
  c.strict = false
  c.observe_coercions = Rails.env.production?   # while the migration runs
end
Accord.freeze!
```

---

## Behavioral differences to watch

Accord is not a drop-in re-implementation of `permit` + `ActiveModel::Type` — it canonicalizes, and canonicalization changes behavior at the margin. These are the ones that bite in practice:

**Coercion and canonicalization**

- **Currency formatting is accepted.** `"$1,000.00"` and `"1,000"` now parse to `BigDecimal("1000.00")`; the old `to_d`/AR-cast path typically produced `0` or garbage for those. Usually an improvement — but if anything downstream *counted on* rejection, it changes.
- **Booleans differ from `ActiveModel::Type::Boolean`.** ActiveModel treats everything outside its false-list as true — so `"no"` casts to `true` and `""` to `nil`. Accord parses `"no"` → `false` and errors on `""` ([`types/boolean.rb`](../lib/accord/types/boolean.rb)). Checkbox-driven forms sending unusual values are the place to look.
- **Strings are stripped by default** ([`types/string.rb`](../lib/accord/types/string.rb) `strip: true`); strong params passed whitespace through. Pass `strip: false` for fields where surrounding whitespace is significant.
- **Case-folding.** `uuid` canonicalizes to lowercase. If anything compares IDs case-sensitively against stored mixed-case values, canonicalization will surface it.
- **Rounding is never silent.** An AR `decimal` column quietly rounds `"10.999"` on cast; Accord's `decimal`/`currency` reject excess precision with `:invalid_scale` unless you opt into `round: true`. If shadow traffic shows real clients sending extra precision, decide: `round: true` (preserve old behavior) or a 422 (tighten the contract).
- **`:required` accepts `""`.** It rejects absent and explicit-null, but an empty string is a present value. Rails `presence: true` rejects `""`. Cover blank-rejection with `length 1..` on the field or the model validation you kept.

**Request semantics**

- **Missing root key: 400 → 422.** `params.require(:employee)` raised `ParameterMissing` (400); Accord parses a missing `from:` source as empty and returns required-field 422s.
- **Undeclared params are silently ignored.** `action_on_unpermitted_parameters = :log`/`:raise` no longer sees them for migrated endpoints — the schema never reads them. If you relied on those logs to catch client typos, `accord.parse.*` metrics are the replacement signal (a misspelled required field shows up as `:required`).
- **PATCH: use `to_h(compact: true)`.** The legacy `permit` hash contained only sent keys; plain `to_h` contains *every* field (defaults applied, absent fields `nil`) and will stomp columns in an `update!`. `to_h(compact: true)` keeps only keys the request carried — nulls included, absent dropped ([rails.md](rails.md#partial-updates-patch)). This is the single most common migration bug; make it a review-checklist item for every `update` action.
- **Defaults become explicit.** A schema `default:` means every create sends the value to the model, where before the DB default fired. Same result usually — different if the DB default and the documented API default have drifted apart (which the migration will helpfully expose).

**Client-visible**

- **The 422 body changes** unless you override `render_accord_errors` ([Coexistence](#error-responses)). Message text may differ even then.
- **All errors at once.** Accord reports every problem in one pass where model validations may have been conditional or ordered. More errors per response is better for clients, but snapshot-based client tests will notice.

**How to catch all of this:** characterization tests plus the shadow. Before migrating an endpoint, write request specs that pin the *current* behavior for a handful of representative payloads — valid, blank strings, junk types, extra keys, a PATCH with a subset of fields — asserting status and body. Migrate, run them, and triage each diff as "intended tightening" or "regression". The shadow phase then covers the payloads your specs didn't think of, because production clients are more creative than test authors.

---

## Tooling and rollout

### Inventory: what's left

Progress needs a denominator. Cross routes against declared inputs — `Accord::ControllerHelpers.controller_inputs` enumerates every controller's `accord` declarations after eager-loading ([`controller_helpers.rb`](../lib/accord/controller_helpers.rb)):

```ruby
# lib/tasks/accord_inventory.rake
namespace :accord do
  desc "List routed controllers by Accord adoption"
  task inventory: :environment do
    Rails.application.eager_load!
    covered = Accord::ControllerHelpers.controller_inputs
    # => { "EmployeesController" => { employee: CreateEmployee }, ... }

    routed = Rails.application.routes.routes
                  .filter_map { |r| r.defaults[:controller] }
                  .uniq.sort
                  .map { |c| "#{c.camelize}Controller" }   # "admin/employees" -> "Admin::EmployeesController"

    done, todo = routed.partition { |name| covered.key?(name) }
    todo.each { |name| puts "todo    #{name}" }
    done.each { |name| puts "accord  #{name}  (#{covered[name].keys.join(", ")})" }
    puts "\n#{done.size}/#{routed.size} controllers declare Accord inputs"
  end
end
```

Granularity caveat: `controller_inputs` is per-controller (reader → schema), not per-action — a controller counts as "covered" once it declares any input. For per-action truth, also grep for surviving `permit`/`params.require` calls (`rg -l "\.permit\(" app/controllers`) — a migrated controller should have none. Track the two numbers (controllers covered, `permit` call sites remaining) on a dashboard or in CI output; trend lines keep a long migration honest.

### Phased rollout

For an app with hundreds of controllers, expect quarters, not weeks. A shape that works:

- **Phase 0 — plumbing (a day).** Add `gem "accord", require: "accord/rails"`, the initializer with the notification subscriber, the `render_accord_errors` override preserving your legacy 422 shape, the shadow concern, and the rake tasks. Nothing behavioral changes.
- **Phase 1 — new code (immediately, forever).** New endpoints use `accord`; the inventory task's denominator stops growing. Add a lint or review rule against new `permit` calls.
- **Phase 2 — pilot (2-3 controllers, a couple of weeks).** Seed schemas with the draft task, shadow, watch the events, flip, delete legacy code, write down every behavioral difference you hit. The written list is the deliverable — it becomes the team's review checklist.
- **Phase 3 — cohorts.** Convert controller-by-controller, grouped by area/team. Input side only; models and serializers untouched. Shadow the high-traffic ones; low-traffic internal endpoints can flip on characterization tests alone.
- **Phase 4 — tighten.** `observe_coercions` on, per-boundary `strict:` where clients are canonical, dedupe input-shape model validations, `Accord.freeze!`.
- **Phase 5 — dividends.** Wire `Accord.openapi_schemas` into rswag ([openapi.md](openapi.md#rswag)), generate RBS/RBI ([typing.md](typing.md)) — one contract, projected everywhere. These aren't part of the migration's critical path, which is exactly why they come last.

---

See also: [rails.md](rails.md) · [errors.md](errors.md) · [openapi.md](openapi.md) · [getting_started.md](getting_started.md)
