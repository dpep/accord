# frozen_string_literal: true

# Illustrative Rails setup — copy the pieces into a real app (this file needs
# Rails to run). It shows the full controller flow: typed input via the `accord`
# macro (named, inline, and scoped sources), defaults, automatic 422s, and a
# custom error format. See docs/rails.md for the narrated version.

# --- Gemfile -----------------------------------------------------------------
#
#   gem "accord", require: "accord/rails"   # Railtie auto-includes the controller helpers
#   gem "money"                             # only if you use money / iso_currency

# --- app/schemas/create_employee.rb ------------------------------------------

class CreateEmployee < Accord::Schema
  string   :name, :required
  currency :salary, :positive
  boolean  :active, default: true        # default: absent input -> true
  string   :role, default: "member"      # default: absent input -> "member"
  date     :hired_on

  # Block form: reach for it when a field needs several rules or a custom check.
  string :email, :required do
    format(/\A[^@\s]+@[^@\s]+\z/)
    length 5..255
  end
end

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

# --- app/controllers/employees_controller.rb ---------------------------------

class EmployeesController < ApplicationController
  # Three inputs, three source styles:
  accord :employee, CreateEmployee                        # (1) default — reads `params`
  accord :search, from: :q do                             # (2) Symbol — reads params[:q]
    string  :name
    boolean :active
  end
  # (3) list + proc — `[CreateEmployee]` parses an array (the reader returns an
  # array of parsed inputs); the proc pulls each JSON:API resource's attributes
  # out. Errors carry the row index, e.g. [2, :salary].
  accord :batch, [CreateEmployee], from: -> { Array(params[:data]).map { |r| r[:attributes] } }

  # POST /employees  { "name": "Ada", "email": "ada@x.co", "salary": "$65,000" }
  # -> 201 (active defaults to true, role to "member"), or 422 if invalid.
  def create
    render json: Employee.create!(employee.to_h), status: :created  # typed; 422 if invalid
  end

  # GET /employees?q[name]=ada&q[active]=true
  def index
    scope = Employee.all
    scope = scope.where("name ILIKE ?", "%#{search.name}%") if search.name
    scope = scope.where(active: search.active)              unless search.active.nil?
    render json: scope
  end

  # POST /employees/import
  #   { "data": [ { "type": "employees", "attributes": { "name": "Ada", ... } }, ... ] }
  def import
    Employee.insert_all!(batch.map(&:to_h))   # all-or-nothing: one 422 lists every bad row
    head :created
  end
end

# --- The contract DSL: accepts / returns -------------------------------------
#
# `accord` (above) gives named readers; `accepts`/`returns` declare a per-action
# contract — request AND response — right on the action, and become the source
# for OpenAPI *path* generation. Reach for it when you want the documented
# contract; `accord` when you just want typed input.

class EmployeeView < Accord::Schema   # a response contract is just a Schema, used via dump
  uuid     :id
  string   :name
  currency :salary
  boolean  :active
end

class EmployeesApiController < ApplicationController
  accepts CreateEmployee, as: :employee   # typed reader `employee` (as: -> Sorbet-typed)
  returns 201 => EmployeeView, 422 => :errors
  def create
    render json: EmployeeView.dump!(Employee.create!(employee.to_h)), status: :created
  end

  accepts do                              # anonymous input schema, named from the action
    string  :name
    boolean :active
  end
  returns 200 => [EmployeeView]           # a list response
  def index
    render json: input.to_h   # `input` is the default reader (rename via Accord.config.input_reader)
  end
end

# Generate the OpenAPI document from every declared contract (e.g. a rake task):
#
#   Rails.application.eager_load!
#   doc = Accord::ControllerHelpers.openapi_document(info: { title: "API", version: "v1" })
#   File.write("openapi.json", JSON.pretty_generate(doc))
#
# `doc` has full `paths` (verb + path from your routes), `components.schemas`
# (CreateEmployee, EmployeeView, ...), and a shared `components.responses`
# AccordErrors for every `422 => :errors`.

# --- Notes -------------------------------------------------------------------
#
# * No strong-params `permit`: the schema is the allowlist — undeclared params
#   (e.g. `admin`) are ignored.
# * Invalid input raises Accord::InvalidInput, rendered as a 422 by a
#   rescue_from installed when the concern is included. The action body never
#   runs on bad input.
# * Inline schemas are named as controller constants (`search` ->
#   `EmployeesController::SearchInput`), so they still project to OpenAPI/RBS/RBI;
#   pass `const:` to choose the name, and accord refuses to clobber an existing
#   non-schema constant.
# * Observability: subscribe to `accord.parse.*` ActiveSupport notifications to
#   track malformed-input rates (great during an API migration).
