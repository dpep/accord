# frozen_string_literal: true

# Illustrative Rails setup — copy the pieces into a real app (this file needs
# Rails to run). It shows the full controller flow: typed input via the `accord`
# macro, automatic 422s, a custom error format, and query-param filters.
# See docs/rails.md for the narrated version.

# --- Gemfile -----------------------------------------------------------------
#
#   gem "accord", require: "accord/rails"   # Railtie auto-includes the controller helpers
#   gem "money"                             # only if you use money / iso_currency

# --- app/schemas/create_employee.rb ------------------------------------------

class CreateEmployee < Accord::Schema
  string   :name, :required
  string   :email, :required do
    format(/\A[^@\s]+@[^@\s]+\z/)
  end
  currency :salary, :positive
  boolean  :active, default: true
  date     :hired_on
end

# --- app/schemas/employee_filters.rb -----------------------------------------

class EmployeeFilters < Accord::Schema
  string  :department
  boolean :active
  integer :min_salary do
    min 0
  end
end

# --- app/controllers/application_controller.rb -------------------------------

class ApplicationController < ActionController::API
  private

  # Override the default 422 body once, app-wide. `error.errors` is an array of
  # structured Accord::Error — render whatever shape your clients expect.
  def render_accord_errors(error)
    grouped = error.errors.group_by(&:field).transform_values do |errs|
      errs.map(&:code)
    end
    render json: { errors: grouped }, status: :unprocessable_entity
  end
end

# --- app/controllers/employees_controller.rb ---------------------------------

class EmployeesController < ApplicationController
  # Lazily-parsed, memoized readers. Declaring several is free; each action uses
  # whichever it needs. `from:` scopes the source (defaults to `params`).
  accord :employee, CreateEmployee
  accord :filters,  EmployeeFilters, from: -> { params.fetch(:q, {}) }

  # A block defines the schema inline — handy for a simple, single-use input
  # that doesn't warrant its own class. (Named classes still win when you want
  # reuse, isolated tests, or an OpenAPI/RBS/GraphQL projection.)
  accord :search, from: -> { params.fetch(:q, {}) } do
    string  :name
    boolean :active
  end

  # POST /employees
  #   { "name": "Ada", "email": "ada@example.com", "salary": "$65,000" }
  # -> 201, or 422 { "errors": { "salary": ["not_positive"] } } if invalid.
  def create
    record = Employee.create!(employee.to_h)   # `employee` is typed; raises 422 if invalid
    render json: record, status: :created
  end

  # GET /employees?q[active]=true&q[min_salary]=50000
  def index
    scope = Employee.all
    scope = scope.where(department: filters.department) if filters.department
    scope = scope.where(active: filters.active)         unless filters.active.nil?
    scope = scope.where("salary >= ?", filters.min_salary) if filters.min_salary
    render json: scope
  end
end

# --- Notes -------------------------------------------------------------------
#
# * No strong-params `permit`: the schema is the allowlist — undeclared params
#   (e.g. `admin`) are ignored.
# * Invalid input raises Accord::InvalidInput, rendered as a 422 by a
#   rescue_from installed when the concern is included. The action body never
#   runs on bad input.
# * Observability: subscribe to `accord.parse.*` ActiveSupport notifications to
#   track malformed-input rates (great during an API migration).
