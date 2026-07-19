# frozen_string_literal: true

# Accord + RABL: Accord parses input *in*; RABL serializes objects *out* — they
# meet at two points, shown here. Run it directly:
#
#   ruby examples/rabl.rb
#
# No rabl gem required — the RABL templates are printed as-is, and we show the
# output each would produce from an Accord-parsed input.

require_relative "../lib/accord"
require "json"

class Address < Accord::Schema
  string :city, :required
  string :country, :required
end

class CreateEmployee < Accord::Schema
  string   :name, :required
  currency :salary, :positive
  date     :hired_on
  object   :address, Address
end

def section(title)
  puts "\n== #{title} =="
end

input = CreateEmployee.parse({
  name: "Ada",
  salary: "$65,000.00",
  hired_on: "2026-01-15",
  address: { city: "Paris", country: "FR" },
})

# --- 1. Echo canonical input: Schema#dump is the inverse of parse ------------
# When you want to serialize exactly what you parsed, `dump` gives the canonical
# external representation (BigDecimal -> "65000.00", Date -> "2026-01-15") in one
# call — no template needed.
section "input.dump (canonical external)"
puts JSON.pretty_generate(input.dump)

# --- 2. Render the typed object with a RABL template ------------------------
# A parsed input exposes accessors, so a RABL template renders it like any
# object. `input.salary` is a BigDecimal here; use dump for the canonical string
# form in the payload.
section "The RABL template you'd write (app/views/employees/show.rabl)"
puts <<~RABL
  object @input
  attributes :name, :salary, :hired_on
  child :address do
    attributes :city, :country
  end
RABL

section "What that template produces from `input`"
# Equivalent output, hand-rolled so this script stays dependency-free:
rendered = {
  name: input.name,
  salary: input.salary,          # BigDecimal — RABL would emit it via to_json
  hired_on: input.hired_on,      # Date
  address: { city: input.address.city, country: input.address.country },
}
pp rendered

puts "\nTip: for canonical string forms in the payload, render from input.dump " \
     "(section 1) rather than the raw typed accessors."
