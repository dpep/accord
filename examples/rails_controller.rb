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
  # (3) proc + array field — a JSON:API list arrives as a bare array under
  # `data`; the proc reshapes it into { employees: [...] } so an `array` field
  # parses each element through CreateEmployee (errors nest, e.g.
  # [:employees, 2, :salary]).
  accord :batch, from: -> { { employees: params[:data] } } do
    array :employees, CreateEmployee
  end

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

  # POST /employees/import  { "data": [ { "name": "Ada", ... }, { "name": "Bo", ... } ] }
  def import
    Employee.insert_all!(batch.employees.map(&:to_h))   # all-or-nothing: one 422 lists every bad row
    head :created
  end
end

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
