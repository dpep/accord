# frozen_string_literal: true

# Illustrative Rails setup — copy the pieces into a real app (needs Rails to
# run). It leads with the recommended `accepts`/`returns` contract DSL, then
# shows the lighter `accord` macro. See docs/rails.md for the narrated version.

# --- Gemfile -----------------------------------------------------------------
#
#   gem "accord", require: "accord/rails"   # Railtie auto-includes the controller helpers
#   gem "money"                             # only if you use money / iso_currency

# --- app/controllers/application_controller.rb -------------------------------

class ApplicationController < ActionController::API
  private

  # Override the default 422 body once, app-wide. `error.errors` is an array of
  # structured Accord::Error — render whatever shape your clients expect.
  def render_accord_errors(error)
    grouped = error.errors.group_by(&:field).transform_values { |errs| errs.map(&:code) }
    render json: { errors: grouped }, status: :unprocessable_entity
  end
end

# --- The contract DSL: accepts / returns (recommended) -----------------------
#
# The recommended path. `accepts`/`returns` declare a per-action contract: a
# typed reader (`input` by default), an automatic 422 on bad input (the body
# never runs), and OpenAPI path generation. Start simple, add options as needed.

# (1) Simplest: an anonymous input schema. No separate class — it's named from
# the action (`SearchController::IndexInput`), so it still projects to OpenAPI.
class SearchController < ApplicationController
  accepts do
    string  :name
    boolean :active
  end
  def index
    scope = Employee.all
    scope = scope.where("name ILIKE ?", "%#{input.name}%") if input.name  # `input`: the typed reader
    scope = scope.where(active: input.active)              unless input.active.nil?
    render json: scope
  end
end

# (2) Layer on: a reusable named schema, a response contract, and options.
class CreateEmployee < Accord::Schema
  string   :name, :required
  currency :salary, :positive
  boolean  :active, default: true        # default: absent input -> true
  string   :role, default: "member"      # default: absent input -> "member"
  date     :hired_on

  email :email, :required do             # `email` type validates + canonicalizes; add rules on top
    format(/@gmail\.com\z/i)             # this example accepts only gmail addresses
  end
end

class EmployeeView < Accord::Schema      # a response contract is just a Schema, used in the dump direction
  uuid     :id
  string   :name
  currency :salary
  boolean  :active
end

class EmployeesController < ApplicationController
  accepts CreateEmployee, as: :employee                 # `as:` names the reader (Sorbet-typed)
  returns 201 => EmployeeView                           # 422 => :errors is derived from `accepts`, not declared
  def create
    record = Employee.create!(employee.to_h)            # typed input -> a record
    render json: EmployeeView.parse!(record.attributes).dump, status: :created  # project it back out (canonical)
  end

  returns 200 => [EmployeeView]                          # a list response, no request body
  def index
    render json: Employee.all.map { |e| EmployeeView.parse!(e.attributes).dump }
  end
end

# (3) Versioning: one controller, several API versions. Label each contract with
# `version:`; the reader parses the one matching the request. Suffix the schema
# classes (CreateOrderV2, not V2::CreateOrder).
class CreateOrderV1 < Accord::Schema
  uuid    :product_id, :required
  integer :quantity,   :required
end

class CreateOrderV2 < Accord::Schema
  uuid    :product_id, :required
  integer :quantity,   :required
  string  :coupon                        # v2 adds an optional coupon code
end

class OrdersController < ApplicationController
  accepts CreateOrderV1, version: 1
  accepts CreateOrderV2, version: 2      # 422 is derived per version from each `accepts`
  def create
    # `input` is the schema matching the request's version (a CreateOrderV1 or
    # CreateOrderV2). Branch on YOUR versioning library's accessor — here
    # `request.version` (versionist) — the same source Accord's resolver reads.
    order = Order.new(product_id: input.product_id, quantity: input.quantity)

    if request.version.to_s == "2" && input.coupon      # `coupon` exists only on the v2 schema
      order.discount = Coupon.redeem(input.coupon)       # newer behavior, v2 clients only
    end

    order.save!
    render json: order, status: :created
  end
end

# Accord does NOT detect versions — it delegates. Point the resolver at your
# versioning library's source of truth, once, in an initializer:
#
#   Accord.configure do |c|
#     c.version_resolver = ->(ctrl) { ctrl.request.version }        # versionist
#     # c.version_resolver = ->(ctrl) { ctrl.params[:version] }     # URL segment (/v2/…)
#     # c.version_resolver = ->(ctrl) { RequestStore.store[:api_version] }  # thread-local
#   end
#
# No resolver + versioned contracts -> Accord raises (never the wrong schema).
# Each version gets its own OpenAPI doc: openapi_document(version: 2).

# --- The `accord` macro (lighter alternative) --------------------------------
#
# Prefer accepts/returns for new code — same typed reader, plus a contract and
# OpenAPI. Use `accord` when you want only typed input, no contract. Kept for
# now; we'll revisit it later. Same schemas, three source styles:

class LegacyEmployeesController < ApplicationController
  accord :employee, CreateEmployee                        # (1) default — reads `params`
  accord :search, from: :q do                             # (2) Symbol — reads params[:q]
    string  :name
    boolean :active
  end
  # (3) list + proc — `[CreateEmployee]` parses an array (the reader returns an
  # array of parsed inputs); the proc pulls each JSON:API resource's attributes.
  # Errors carry the row index, e.g. [2, :salary].
  accord :batch, [CreateEmployee], from: -> { Array(params[:data]).map { |r| r[:attributes] } }

  def create
    render json: Employee.create!(employee.to_h), status: :created
  end

  def import
    Employee.insert_all!(batch.map(&:to_h))   # all-or-nothing: one 422 lists every bad row
    head :created
  end
end

# --- Generating the OpenAPI document -----------------------------------------
#
#   Rails.application.eager_load!
#   doc = Accord::ControllerHelpers.openapi_document(info: { title: "API", version: "v1" })
#   File.write("openapi.json", JSON.pretty_generate(doc))
#
# `doc` has full `paths` (verb + path from your routes), `components.schemas`
# (CreateEmployee, EmployeeView, ...), and a shared `components.responses`
# AccordErrors referenced by the derived 422 on every `accepts` action. For a
# versioned API, pass `version:` to scope the document to one version.

# --- Notes -------------------------------------------------------------------
#
# * No strong-params `permit`: the schema is the allowlist — undeclared params
#   (e.g. `admin`) are ignored.
# * Invalid input raises Accord::InvalidInput, rendered as a 422 by a rescue_from
#   installed when the concern is included. The action body never runs on bad input.
# * Anonymous schemas are named as controller constants (`index` ->
#   `SearchController::IndexInput`, a versioned `create` -> `CreateV2Input`), so
#   they still project to OpenAPI/RBS/RBI; pass `const:` to choose the name.
# * Observability: subscribe to `accord.parse.*` ActiveSupport notifications to
#   track malformed-input rates (great during an API migration).
