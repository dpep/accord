# frozen_string_literal: true

# Accord + GraphQL: one schema is both the input contract *and* the GraphQL
# input type. This example (1) generates GraphQL SDL from a schema, and (2)
# shows the resolver pattern — parse resolver args through the schema, then map
# structured errors onto GraphQL's error shape. Run it directly:
#
#   ruby examples/graphql.rb
#
# No graphql gem required — the "resolver" here is a plain method fed a hash,
# exactly what graphql-ruby hands a mutation's #resolve.

require_relative "../lib/accord"

class Address < Accord::Schema
  string :city, :required
  string :country, :required
end

class LineItem < Accord::Schema
  string  :sku, :required
  integer :quantity, :required, between: 1..999
end

class CreateOrder < Accord::Schema
  string  :email, :required
  object  :address, Address, :required
  array   :line_items, LineItem
  money   :total
  boolean :gift, default: false
  date    :deliver_on
end

def section(title)
  puts "\n== #{title} =="
end

# --- 1. Generate GraphQL SDL from the schema --------------------------------
# Schema.graphql emits one input type; Schema.graphql_schemas emits the whole
# graph (nested object/array inputs + MoneyInput), ready to join into a doc.
section "Generated SDL (CreateOrder.graphql_schemas)"

puts CreateOrder.graphql_schemas.values.join("\n\n")

# --- 2. The resolver pattern -------------------------------------------------
# A graphql-ruby mutation receives its arguments as a hash. Parse them through
# the schema to coerce + validate; Accord::Error#path maps onto a GraphQL error
# path directly.
def resolve_create_order(args)
  input = CreateOrder.parse(args)

  return { data: nil, errors: user_errors(input.errors) } unless input.valid?

  # input is now typed: input.total is a Money, input.deliver_on a Date, etc.
  { data: { email: input.email, total: input.dump[:total] }, errors: [] }
end

def user_errors(errors)
  # Accord errors are structured data — rendering is a separate concern. Here we
  # map straight onto GraphQL's error shape; `path` drops in as-is. For a
  # human `message`, render via Accord::Messages (require "accord/i18n") or your
  # own i18n layer keyed on `code`.
  errors.map do |e|
    { message: e.code.to_s, path: e.path, extensions: { code: e.code, validator: e.validator } }
  end
end

section "Resolve valid args"
pp resolve_create_order(
  email: "ada@example.com",
  address: { city: "Paris", country: "FR" },
  line_items: [{ sku: "A1", quantity: "2" }],
  total: { amount: "49.99", currency: "eur" },
)

section "Resolve invalid args (errors carry GraphQL-ready paths)"
pp resolve_create_order(
  email: "ada@example.com",
  address: { city: "Paris" },                       # missing country
  line_items: [{ sku: "A1", quantity: "0" }],       # out of range -> [:line_items, 0, :quantity]
)
