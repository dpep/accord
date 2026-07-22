# Accord in Rails controllers

Accord's sweet spot is the controller boundary: turn untrusted `params` into a **typed, validated input object** with one declaration, and let malformed requests become a `422` automatically. The recommended path is the **`accepts`/`returns` contract DSL** — a documented per-action request/response contract that also drives OpenAPI. A lighter `accord` macro (typed readers, no contract) remains for simple cases, but new code should prefer `accepts`/`returns`. This guide covers the full flow — setup, contracts, error rendering, query params, testing, and observability.

- [Setup](#setup)
- [Your first controller](#your-first-controller)
- [The contract DSL: `accepts` / `returns`](#the-contract-dsl-accepts--returns)
  - [The typed reader](#the-typed-reader)
  - [Scoping input: `from:` and `strict:`](#scoping-input-from-and-strict)
  - [Inline schemas](#inline-schemas)
  - [List inputs](#list-inputs)
  - [Partial updates (PATCH)](#partial-updates-patch)
  - [The response contract: `returns`](#the-response-contract-returns)
  - [OpenAPI generation](#openapi-generation)
  - [Introspection](#introspection)
  - [Versioning](#versioning)
- [The `accord` macro (lighter alternative)](#the-accord-macro-lighter-alternative)
- [Calling a schema directly](#calling-a-schema-directly)
- [Rendering errors](#rendering-errors)
- [Query params and filters](#query-params-and-filters)
- [Strong Parameters](#strong-parameters)
- [Strict mode](#strict-mode)
- [Observability](#observability)
- [From permissive to strict](#from-permissive-to-strict)
- [Testing controllers](#testing-controllers)

---

## Setup

Accord's core carries no Rails dependency. Load the opt-in integration from your `Gemfile`:

```ruby
gem "accord", require: "accord/rails"
```

`accord/rails` does two things: wires permissive-parse events to `ActiveSupport::Notifications`, and installs a Railtie that includes `Accord::ControllerHelpers` into your controllers (via `ActiveSupport.on_load(:action_controller)`). Nothing else to configure.

Define schemas wherever you like — a common home is `app/schemas`:

```ruby
# app/schemas/create_employee.rb
class CreateEmployee < Accord::Schema
  string   :name, :required
  email    :email, :required do
    format(/@gmail\.com\z/i)   # `email` validates + canonicalizes; this example accepts only gmail
  end
  currency :salary, :positive
  boolean  :active, default: true
  date     :hired_on
end
```

---

## Your first controller

Declare the request contract with `accepts` (naming the reader with `as:`), then use the memoized reader (`employee`) in your action:

```ruby
class EmployeesController < ApplicationController
  accepts CreateEmployee, as: :employee

  def create
    record = Employee.create!(employee.to_h)
    render json: record, status: :created
  end
end
```

That's the whole happy path. `employee` parses `params` the first time it's called and returns a typed `CreateEmployee` instance:

```ruby
employee.name      # => "Ada"      (String)
employee.salary    # => 0.65e5     (BigDecimal — never a Float)
employee.active    # => true       (Boolean, defaulted)
employee.hired_on  # => #<Date ...>
employee.to_h      # => { name: "Ada", email: "...", salary: ..., active: true, hired_on: ... }
```

`to_h` is a deep Hash of **typed** values (nested schemas recurse to Hashes too) — hand it to `Model.new`/`create!`. To **serialize** (render JSON), use `dump`, which emits the canonical *external* form — strings like `"65000.00"` and `"2026-01-15"`: `render json: employee.dump`.

If the request is invalid, calling `employee` raises `Accord::InvalidInput`, which a `rescue_from` (installed when the concern is included) turns into a `422` with the structured errors — your action body never runs. A request like `POST /employees` with `{ "salary": "-5", "email": "ada@yahoo.com" }` yields:

```json
{
  "errors": [
    { "path": ["name"],   "field": "name",   "code": "required" },
    { "path": ["email"],  "field": "email",  "code": "invalid_format", "validator": "format", "value": "ada@yahoo.com", "pattern": "@gmail\\.com\\z" },
    { "path": ["salary"], "field": "salary", "code": "not_positive",   "validator": "positive", "value": "-5.00" }
  ]
}
```

Note that **every** error is reported, not just the first — Accord parses the whole request in one pass (see [errors.md](errors.md)).

---

## The contract DSL: `accepts` / `returns`

`accepts` and `returns` declare a **per-action contract** — request schema in, response schema(s) out — right on the action, `sig`-style. It's the recommended default: the same typed reader you just saw, plus a documented contract that drives OpenAPI *path* generation. (The lighter [`accord` macro](#the-accord-macro-lighter-alternative) gives you named readers with no contract when that's all you want.)

```ruby
class EmployeesController < ApplicationController
  accepts CreateEmployee, as: :employee
  returns 201 => EmployeeView          # 422 is automatic — any `accepts` action can fail validation
  def create
    record = Employee.create!(employee.to_h)
    render json: EmployeeView.parse!(record.attributes).dump, status: :created
  end

  accepts do                       # anonymous schema, named EmployeesController::IndexInput
    string  :name
    boolean :active
  end
  returns 200 => [EmployeeView]    # a list response
  def index
    render json: Employee.where(input.to_h).map { |e| EmployeeView.parse!(e.attributes).dump }
  end
end
```

Both decorators bind to the **next `def`** and compose; either or both is fine. `accepts` alone is a typed-input endpoint; `returns` alone is an output-only projection.

### The typed reader

The reader is `input` by default. It's action-dispatched — it parses whatever schema the *current* action declared — so it's a single method shared by every action, not one per action. That polymorphism is also why `input` can't be statically typed.

Two ways to rename it:

- **Per-action with `as:`** — `accepts CreateEmployee, as: :employee` gives that action an `employee` reader. Because an `as:`-named reader is unique to one action, it *can* be statically typed (Sorbet/RBI), so prefer `as:` when you want the typed reader inside the action.
- **Globally with `Accord.config.input_reader`** — rename the default from `input` to whatever your house style prefers.

The reader is lazy and memoized: the schema parses on first access and only once, so declaring a contract costs nothing in an action that never touches it. Undeclared input keys are silently dropped — in permissive and strict mode alike, never an error (the schema is the allowlist; see [Strong Parameters](#strong-parameters)).

### Scoping input: `from:` and `strict:`

By default the reader parses all of `params`. Two options narrow or tighten that:

- **`from:`** scopes the source. A **Symbol** names a params key (`from: :q` → `params[:q]`) for the common nested case; a **proc**, evaluated in controller context, handles anything a single key can't (`from: -> { params.dig(:data, :attributes) }`).
- **`strict:`** — `accepts CreateEmployee, strict: true` rejects loose input at this endpoint (overriding `Accord.config.strict`); a bad or missing value renders a `422` like any other client data. See [Strict mode](#strict-mode) for what "strict" changes.

### Inline schemas

Pass a block instead of a schema class to define the schema right on the action — handy for a simple, single-use input that doesn't warrant its own file:

```ruby
accepts from: :q do
  string  :name
  boolean :active
end
def index
  render json: Employee.where(input.to_h)
end
```

The inline schema is named from the action (`index` → `EmployeesController::IndexInput`, a versioned `create` → `CreateV2Input`), so it still projects to OpenAPI/RBS/RBI. Pass `const:` to choose the name (`accepts const: :SearchParams do … end`); Accord refuses to clobber an existing constant that isn't itself a schema. Reach for a top-level named class when you want reuse across controllers or isolated schema tests.

### List inputs

Wrap the schema in a one-element array to parse a **list** — the reader returns the parsed elements, and errors carry each element's index (`[2, :salary]`, no wrapper key):

```ruby
accepts [CreateEmployee], from: :employees, as: :batch   # params[:employees] is an array

def import
  Employee.insert_all!(batch.map(&:to_h))                # one 422 lists every bad row
end
```

Like an inline block, this mints a constant — an `Accord::Schema::List` (`BatchInput`) whose projection methods are array-shaped: `.openapi` → `{ type: array, items: $ref }`, `.rbs` → `Array[CreateEmployee]`, `.graphql` → `[CreateEmployeeInput!]!`. Because it's a list wrapper (not a `Schema` subclass), it isn't a standalone named type — `tapioca dsl` and `accord:rbs` emit the *element* (`CreateEmployee`), and you reference the list type inline.

### Partial updates (PATCH)

Accord distinguishes an **absent** field from one sent as **explicit null**, which is exactly the PATCH contract — an absent field is left untouched, a null clears it. An explicit null yields `nil` (skipping any default); `to_h(compact: true)` returns only the fields the request actually carried a key for (keeping nulls, dropping absent):

```ruby
accepts CreateEmployee, as: :employee
returns 204 => nil
def update
  # PATCH /employees/1  { "email": null }   -> clears email, leaves everything else alone
  Employee.find(params[:id]).update!(employee.to_h(compact: true))
  head :no_content
end
```

Use `input.present?(:field)` to test whether a key was supplied. (Plain `to_h` is the create shape — every field, defaults applied.)

### The response contract: `returns`

`returns` maps `status => contract`, where a contract is one of:

- a **`Schema`** — the response body, used in the dump direction (`201 => EmployeeView`)
- a **`[Schema]`** list — a JSON array of that schema (`200 => [EmployeeView]`)
- **`:errors`** — the shared structured-error response, the same shape [`render_accord_errors`](#rendering-errors) emits
- **`nil`** — no body (`204 => nil`)

**You don't declare `422 => :errors`.** Any action with an `accepts` contract can fail validation, so Accord derives the `422 => :errors` response for it automatically — it's implied by the request contract, not repeated on every `returns`. (Declaring it explicitly is harmless but redundant. An output-only action, with no `accepts`, gets no derived 422.) The `:errors` symbol is still there for the rare case you want that response on an action without an `accepts`.

Responses are ordinary `Accord::Schema`s used in the dump direction — no separate serializer concept. There's no `Schema.dump!` class method: to project a record through a response schema, coerce it to canonical external form with `EmployeeView.parse!(record.attributes).dump` — parse the record's attributes into a typed instance, then `#dump` it. For a one-off response shape easier to declare inline than to name, `returns` also takes a block form — an anonymous response schema, named from the action like an inline `accepts`: `returns(201) { string :location }`.

On `returns`, `version:` is a reserved key inside the responses hash (statuses are Integers, so it can't collide) — see [Versioning](#versioning).

### OpenAPI generation

Every contract feeds OpenAPI path generation. Eager-load, then ask for the document:

```ruby
Rails.application.eager_load!
doc = Accord::ControllerHelpers.openapi_document(info: { title: "API", version: "v1" })
File.write("openapi.json", JSON.pretty_generate(doc))
```

`doc` has full `paths` (verb + path pulled from your routes), `components.schemas` (`CreateEmployee`, `EmployeeView`, …), and a shared `components.responses` `AccordErrors` referenced by the derived `422` on every `accepts` action. `openapi_document` accepts `info:`, `version:` (scope to one API version), `endpoints:` (a specific set instead of the whole app), and `resolver:` (override version resolution). See [openapi.md](openapi.md).

### Introspection

The whole contract graph is introspectable:

- `Controller.accord_endpoints` — an Array of `Accord::Endpoint` for one controller.
- `Accord::ControllerHelpers.endpoints` — every endpoint across the app.

That's what the OpenAPI generator walks; you can walk it too, for docs, route audits, or contract tests.

### Versioning

For a single controller serving multiple API versions, label each contract with `version:` — one `accepts`/`returns` per version:

```ruby
accepts CreateEmployeeV1, version: 1
returns 201 => EmployeeViewV1, version: 1

accepts CreateEmployeeV2, version: 2
returns 201 => EmployeeViewV2, 202 => AsyncReceipt, version: 2
def create
  record = Employee.create!(input.to_h)             # `input` resolves the request's version
  render json: record, status: :created
end
```

`version:` is a plain label — an Integer, or any value (`"2024-01"`, `"v2"`); Accord is unopinionated about its shape. Labels are matched exactly, as strings (`label.to_s == resolved.to_s`), so `1` matches `"1"` but `"V2"` won't match `"v2"` and `" 2"` won't match `"2"` — pick one canonical spelling and have your resolver emit it. On `accepts` `version:` is a keyword; on `returns` it's a reserved key inside the responses hash (statuses are Integers, so it can't collide). Suffix versioned schema classes (`CreateEmployeeV1`, not `V1::CreateEmployee`) — Accord follows the same convention for auto-named anonymous version blocks (`accepts version: 2 do … end` → `CreateV2Input`). An **unversioned** `returns` is shared into every version (handy for a response common to all versions); an unversioned `accepts` alongside versioned ones is ambiguous and rejected. (The `422` is derived per version from each `accepts`, so you never repeat it.)

**Accord does not detect versions — it delegates.** Version negotiation (headers, URL segments, `Accept` media types, deprecation windows) is your API versioning library's job; Accord only maps the version *it already resolved* to a `version:` contract. Give it one hook — `Accord.config.version_resolver`, a `->(controller) { … }` returning the request's version — pointed at your library's source of truth:

```ruby
Accord.configure do |c|
  c.version_resolver = ->(ctrl) { ctrl.request.version }              # versionist
  # c.version_resolver = ->(ctrl) { ctrl.params[:version] }           # URL segment (/v2/…)
  # c.version_resolver = ->(ctrl) { RequestStore.store[:api_version] } # middleware / thread-local
  # c.version_resolver = ->(ctrl) { ctrl.request.headers["Accept"][/vnd\.myapp\.v(\d+)/, 1] }  # media type
end
```

The reader parses the contract whose `version:` matches the resolved value, falling back to the unversioned one. With versioned contracts declared but **no resolver set, Accord raises `Accord::ConfigurationError`** — at boot via `Accord.freeze!` (call it after eager-load), and again at request time as a backstop — rather than silently serving the wrong schema. A resolved version that matches no contract also raises (your versioning layer should reject unsupported versions before dispatch). Inside an action, branch on your *versioning library's* accessor (e.g. `request.version`) — the same source the resolver reads — not on Accord internals.

For header or media-type versioning, each version projects to its **own** OpenAPI document — `Accord::ControllerHelpers.openapi_document(info:, version: 2)` — because those versions share a `path + verb` and a header can't distinguish them in one operation; unversioned endpoints are included in every version's doc. URL-segment versioning (`/v1/…` vs `/v2/…`) has distinct paths, so it can emit a single combined document (omit `version:`).

---

## The `accord` macro (lighter alternative)

> Prefer [`accepts`/`returns`](#the-contract-dsl-accepts--returns) for new code — it gives the same typed reader plus a documented contract and OpenAPI. `accord` is the lighter option when you want *only* typed input and no contract; we're keeping it for now and will revisit its role after more real-world use.

`accord :name, Schema` defines a **lazily-parsed, memoized reader** named `name`. It's not an action hook — it's just a reader — so a controller can declare several inputs and each action uses whichever it needs:

```ruby
class EmployeesController < ApplicationController
  accord :employee, CreateEmployee
  accord :filters,  EmployeeFilters, from: -> { params.fetch(:q, {}) }

  def index
    render json: Employee.where(filters.to_h)   # uses `filters`
  end

  def create
    render json: Employee.create!(employee.to_h), status: :created  # uses `employee`
  end
end
```

`accord` shares the same declaration options as `accepts` — `from:` (Symbol or proc), `strict:`, an inline block schema (`accord :search, from: :q do … end`, named `SearchController::SearchInput`, `const:` to override), and list inputs (`accord :batch, [CreateEmployee], from: :employees`). The difference is scope: `accord` gives you named readers, full stop — no response contract, no OpenAPI path.

- **Lazy** — the schema parses on first access, so declaring an input costs nothing in actions that don't use it. **Memoized** — accessing `employee` twice parses once.
- **Typed** — with Sorbet, the bundled Tapioca DSL compiler types each reader from its schema (`employee` → `CreateEmployee`, a `[Schema]` list → `T::Array[CreateEmployee]`), so `employee.salary` type-checks inside the action. Run `bundle exec tapioca dsl`.
- **Introspectable** — the declarations live in `Controller.accord_inputs` (`{ reader_name => schema }`), e.g. to enumerate every controller's inputs for docs.

To fail before the action body (eager validation), name the reader in a `before_action`:

```ruby
before_action :employee, only: :create
```

---

## Calling a schema directly

The macro is sugar; the schema is the real entry point. `Schema.parse!(params)` returns the typed input or raises `Accord::InvalidInput`:

```ruby
def create
  input = CreateEmployee.parse!(params)
  EmployeeService.call(input)
  head :created
end
```

The same `rescue_from` renders the `422`. Use this when a schema is chosen dynamically, or when you prefer an explicit call over a declaration.

If you want to branch on validity yourself instead of raising, use permissive `parse`:

```ruby
input = CreateEmployee.parse(params)

if input.valid?
  EmployeeService.call(input)
else
  render json: { errors: input.errors.map(&:to_h) }, status: :unprocessable_entity
end
```

---

## Rendering errors

The concern ships a default renderer and lets you override one method. The default:

```ruby
render json: { errors: error.errors.map(&:to_h) }, status: :unprocessable_entity
```

Override `render_accord_errors` — typically in `ApplicationController`, so every controller inherits it:

```ruby
class ApplicationController < ActionController::API
  private

  def render_accord_errors(error)
    render json: ErrorSerializer.new(error.errors), status: :unprocessable_entity
  end
end
```

`error` is the `Accord::InvalidInput` exception; `error.errors` is the array of `Accord::Error`. Because errors are **structured data, not strings** (`path`, `code`, `validator`, `value`, metadata — see [errors.md](errors.md)), you can render whatever shape a client needs.

### Rails-style `{ field => [messages] }` (i18n)

Accord ships localized messages and an `ActiveModel::Errors`-style renderer, `Accord::Messages` (loaded by `accord/rails`). Use it directly in your override:

```ruby
def render_accord_errors(error)
  render json: { errors: Accord::Messages.messages(error.errors) }, status: :unprocessable_entity
end
# => { "errors": { "salary": ["must be positive"], "name": ["is required"] } }
```

`Accord::Messages` mirrors the API you know — `message`, `full_message`, `messages`, `full_messages`. Messages come from the shipped `accord.errors.<code>` locale, and you override any of them (or translate to another locale) in your own `config/locales`. Metadata like `expected`/`min`/`max` is interpolated automatically. See [errors.md](errors.md#i18n).

### GraphQL

The `path` array drops straight into a GraphQL error's `path`:

```ruby
error.errors.map { |e| { message: I18n.t("errors.#{e.code}"), path: e.path, extensions: { code: e.code } } }
```

### i18n

`code` + `field` + `metadata` give you everything a translation needs:

```ruby
I18n.t("accord.errors.#{error.code}", field: error.field, **error.metadata)
# e.g. accord.errors.too_small: "%{field} must be at least %{expected}"
```

---

## Query params and filters

Query strings are just params. Scope a filter schema with `from:` and keep every field optional (a filter you didn't send simply stays `nil`):

```ruby
class EmployeeFilters < Accord::Schema
  string  :department
  boolean :active
  integer :min_salary do
    min 0
  end
end

class EmployeesController < ApplicationController
  accepts EmployeeFilters, as: :filters, from: -> { params.fetch(:q, {}) }

  def index
    scope = Employee.all
    scope = scope.where(department: filters.department) if filters.department
    scope = scope.where(active: filters.active)         unless filters.active.nil?
    scope = scope.where("salary >= ?", filters.min_salary) if filters.min_salary
    render json: scope
  end
end
```

`GET /employees?q[active]=true&q[min_salary]=50000` coerces `"true" → true` and `"50000" → 50000`, and a bad `q[min_salary]=-1` is a `422` with `code: :too_small`.

---

## Strong Parameters

You don't need `permit`. **The schema is the allowlist**: it reads only its declared fields, via `[]`/`key?`, which `ActionController::Parameters` permits without permitting. Undeclared params are ignored — in permissive and strict mode alike, never an error — so an attacker can't set fields you didn't ask for.

```ruby
# params: { name: "Ada", salary: "50000", admin: true }
CreateEmployee.parse!(params).to_h
# => { name: "Ada", salary: 0.5e5, active: true, hired_on: nil }   # `admin` never appears
```

Nested payloads work the same way — `object`/`array` fields read nested `ActionController::Parameters` and arrays directly:

```ruby
class CreateOrder < Accord::Schema
  object :customer, CustomerInput
  array  :line_items, LineItemInput
end
# POST { customer: { ... }, line_items: [ {...}, {...} ] }  ->  typed, with nested error paths
```

---

## Strict mode

By default controllers parse **permissively**: legacy/loose input is coerced (`"true" → true`, `"$1,000" → BigDecimal`) and every problem is collected. That's usually what you want at a public boundary.

`parse!` is strict about *validity* (it raises if the result is invalid) but still permissive about *coercion*. For a fully strict boundary that rejects loose input on the first coercion failure, pass `strict:`:

```ruby
CreateEmployee.parse!(params, strict: true)   # raises Accord::CoercionError on the first bad coercion
```

Flip the default globally in an initializer (per-call `strict:` still wins):

```ruby
# config/initializers/accord.rb
Accord.configure do |c|
  c.strict = false           # default parse mode
  c.default_currency = "USD"   # makes money fields' currency optional
  c.notifications = true       # emit accord.parse.<code> events (default on)
  c.observe_coercions = false  # emit accord.parse.coerced (default off; see below)
end
```

---

## Observability

Every error tolerated by a permissive parse emits an `ActiveSupport::Notifications` event named `accord.parse.<code>`, wired up by `accord/rails`. Subscribe to track malformed-input rates, drive alerts, or debug an API migration.

The simplest useful subscriber just logs each tolerated error:

```ruby
# config/initializers/accord_logging.rb
ActiveSupport::Notifications.subscribe(/accord\.parse/) do |name, _start, _finish, _id, payload|
  # name    => "accord.parse.invalid_currency"
  # payload => { field: :salary, path: [:salary], validator: :positive, value: ... }
  Rails.logger.info("[accord] #{name} at #{payload[:path].inspect} (#{payload[:field]})")
end
```

Or push counts to a metrics backend:

```ruby
# config/initializers/accord_metrics.rb
ActiveSupport::Notifications.subscribe(/accord\.parse/) do |name, _start, _finish, _id, payload|
  StatsD.increment(name, tags: { field: payload[:field], code: name.split(".").last })
end
```

This is especially useful when migrating an existing API: run permissively, watch the events, and see exactly which fields real clients are getting wrong before you tighten anything.

---

## From permissive to strict

Permissive parsing is a great *starting* point — but the goal is usually to tighten toward strict, canonical input. Accord turns that into an observable, data-driven process rather than a guess.

The events above (`accord.parse.<error_code>`) tell you which fields clients get **wrong**. A second signal tells you which fields still rely on **permissiveness** — i.e. which ones you *can't* make strict yet. Enable it during a migration:

```ruby
# config/initializers/accord.rb
Accord.configure { |c| c.observe_coercions = true }
```

Now, whenever a permissive parse accepts input that strict rules would reject (`"$1,000.00"` for a currency, `"yes"` for a boolean, a legacy date format), Accord emits `accord.parse.coerced` with the raw input it saw:

```ruby
ActiveSupport::Notifications.subscribe("accord.parse.coerced") do |_name, _s, _f, _id, payload|
  # payload => { field: :salary, path: [:salary], input: "$1,000.00", value: 0.1e4, type: :currency }
  Rails.logger.info("[accord] permissive #{payload[:field]} <- #{payload[:input].inspect}")
end
```

The `input` is the **variant** — so you can aggregate "which shapes is this field actually receiving?" and narrow scope gradually. The workflow:

1. **Watch** — run permissively; group `accord.parse.coerced` by field, and by the distinct `input` variants each field sees.
2. **Fix at the source** — once you know the variants (e.g. clients sending `"1,000"` and `"$1000"`), update the offending clients, or normalize upstream.
3. **Flip when quiet** — when the events stop, that traffic is already canonical. Tighten the boundary with `parse!(params, strict: true)` (or `Accord.config.strict = true` globally). If some fields settle before others, split the settled ones into a strict sub-schema and keep the rest permissive.

The signal is off by default (it costs a strict re-check per loose field) and only fires when a notifier is listening, so it's a migration tool you switch on, not steady-state overhead.

---

## Testing controllers

Nothing special — schemas are plain Ruby, so request/controller specs work as usual. The valuable cases are the `422` shape and coercion:

```ruby
RSpec.describe EmployeesController do
  it "creates an employee from valid params" do
    post :create, params: { name: "Ada", email: "ada@example.com", salary: "50000" }
    expect(response).to have_http_status(:created)
  end

  it "returns structured errors for invalid input" do
    post :create, params: { salary: "-5" }
    expect(response).to have_http_status(:unprocessable_entity)
    codes = JSON.parse(response.body)["errors"].map { |e| e["code"] }
    expect(codes).to include("required", "not_positive")
  end
end
```

You can also test schemas in isolation (no controller), which is faster and often clearer — see [validation.md](validation.md).

---

See also: [getting_started.md](getting_started.md) · [types.md](types.md) · [validation.md](validation.md) · [errors.md](errors.md) · [typing.md](typing.md)
</content>
</invoke>
