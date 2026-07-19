# Accord in Rails controllers

Accord's sweet spot is the controller boundary: turn untrusted `params` into a **typed, validated input object** with one declaration, and let malformed requests become a `422` automatically. This guide covers the full flow — setup, the `accord` macro, error rendering, query params, testing, and observability.

- [Setup](#setup)
- [Your first controller](#your-first-controller)
- [The `accord` macro](#the-accord-macro)
- [Calling a schema directly](#calling-a-schema-directly)
- [Rendering errors](#rendering-errors)
- [Query params and filters](#query-params-and-filters)
- [Strong Parameters](#strong-parameters)
- [Strict mode](#strict-mode)
- [Observability](#observability)
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
  string   :email, :required do
    format(/\A[^@\s]+@[^@\s]+\z/)
  end
  currency :salary, :positive
  boolean  :active, default: true
  date     :hired_on
end
```

---

## Your first controller

Declare the input with `accord`, then use the memoized reader (`employee`) in your action:

```ruby
class EmployeesController < ApplicationController
  accord :employee, CreateEmployee

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

If the request is invalid, calling `employee` raises `Accord::InvalidInput`, which a `rescue_from` (installed when the concern is included) turns into a `422` with the structured errors — your action body never runs. A request like `POST /employees` with `{ "salary": "-5", "email": "nope" }` yields:

```json
{
  "errors": [
    { "path": ["name"],   "field": "name",   "code": "required" },
    { "path": ["email"],  "field": "email",  "code": "invalid_format", "validator": "format", "value": "nope", "pattern": "\\A[^@\\s]+@[^@\\s]+\\z" },
    { "path": ["salary"], "field": "salary", "code": "not_positive",   "validator": "positive", "value": "-5.00" }
  ]
}
```

Note that **every** error is reported, not just the first — Accord parses the whole request in one pass (see [errors.md](errors.md)).

---

## The `accord` macro

```ruby
accord :employee, CreateEmployee
accord :filters,  EmployeeFilters, from: -> { params[:q] }
```

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

- **Lazy** — the schema parses on first access, so declaring an input costs nothing in actions that don't use it.
- **Memoized** — accessing `employee` twice parses once.
- **`from:`** — scopes the source (defaults to all of `params`). A **Symbol** names a params key (`from: :q` → `params[:q]`) for the common nested case; a **proc**, evaluated in controller context, handles anything a single key can't (`from: -> { params.dig(:data, :attributes) }`).

### Inline schemas

Pass a block instead of a schema class to define a schema right in the controller — handy for a simple, single-use input that doesn't warrant its own file:

```ruby
accord :search, from: :q do
  string  :name
  boolean :active
end
```

The inline schema is named as a controller constant (`:search` → `SearchController::SearchInput`), so it still projects to OpenAPI/RBS/RBI. Pass `const:` to choose the name (`accord :search, const: :SearchParams do … end`); accord refuses to clobber an existing constant that isn't itself a schema. Reach for a top-level named class when you want reuse across controllers or isolated schema tests. `accord` requires exactly one of a schema class or a block.

### List inputs

Wrap the schema in a one-element array to parse a **list** — the reader returns the parsed inputs, and errors carry each element's index (`[2, :salary]`, no wrapper key):

```ruby
accord :batch, [CreateEmployee], from: :employees   # params[:employees] is an array

def import
  Employee.insert_all!(batch.map(&:to_h))           # one 422 lists every bad row
end
```

Like an inline block, this mints a constant — an `Accord::ListSchema` (`BatchInput`) whose projection methods are array-shaped: `.openapi` → `{ type: array, items: $ref }`, `.rbs` → `Array[CreateEmployee]`, `.graphql` → `[CreateEmployeeInput!]!`. Because it's a list wrapper (not a `Schema` subclass), it isn't a standalone named type — `tapioca dsl` and `accord:rbs` emit the *element* (`CreateEmployee`), and you reference the list type inline. `Accord::ListSchema.new(CreateEmployee)` is usable outside Rails too.

Eager validation (fail before the action body) is just a `before_action`:

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
  accord :filters, EmployeeFilters, from: -> { params.fetch(:q, {}) }

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

You don't need `permit`. **The schema is the allowlist**: it reads only its declared fields, via `[]`/`key?`, which `ActionController::Parameters` permits without permitting. Undeclared params are ignored, so an attacker can't set fields you didn't ask for.

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
