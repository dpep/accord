# frozen_string_literal: true

# A self-contained tour of Accord: define a schema, parse valid and invalid
# input, read typed values, inspect structured errors, and see the OpenAPI /
# RBS projections. Run it directly:
#
#   ruby examples/employee.rb

require_relative "../lib/accord"

class Address < Accord::Schema
  string :city, :required
  string :zip, format: /\A\d{5}\z/
end

class CreateEmployee < Accord::Schema
  string   :name, :required
  string   :email, :required, format: /\A[^@\s]+@[^@\s]+\z/   # keyword shorthand
  boolean  :active, default: true                             # default value
  date     :hired_on
  object   :address, Address

  # Block form: for a custom rule the keyword shorthand can't express.
  currency :salary, :positive do
    validate(:increment) { |v| error(:round_hundreds) unless (v % 100).zero? }
  end
end

def section(title)
  puts "\n== #{title} =="
end

# --- Valid input: loose strings coerce into canonical typed values ----------
section "Valid input"

input = CreateEmployee.parse({
  name: "Ada",
  email: "ada@example.com",
  salary: "$65,000.00",     # currency symbol + comma stripped
  hired_on: "2026-01-15",   # ISO-8601 -> Date
  address: { city: "Paris", zip: "75001" },
})

puts "valid?        #{input.valid?}"
puts "name          #{input.name.inspect}        (#{input.name.class})"
puts "salary        #{input.salary.inspect}   (#{input.salary.class})"
puts "active         #{input.active.inspect}          (defaulted)"
puts "hired_on      #{input.hired_on.inspect}  (#{input.hired_on.class})"
puts "address.city  #{input.address.city.inspect}"

# --- Invalid input: every problem collected in one pass ---------------------
section "Invalid input (nothing raised — errors collected)"

bad = CreateEmployee.parse({
  email: "nope",
  salary: "-5",
  address: { zip: "abc" },   # nested error path
})

puts "valid?  #{bad.valid?}"
bad.errors.each { |e| puts "  #{e.to_h}" }

# --- parse! raises on invalid ------------------------------------------------
section "parse! raises Accord::InvalidInput"

begin
  CreateEmployee.parse!({ salary: "-5" })
rescue Accord::InvalidInput => e
  puts "rescued #{e.class} with #{e.errors.size} errors"
end

# --- Projections: the one declaration also documents & types -----------------
section "Projections"

require "json"
puts "OpenAPI schema:"
puts JSON.pretty_generate(CreateEmployee.openapi)
puts "\nRBS:"
puts CreateEmployee.rbs
