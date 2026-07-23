# frozen_string_literal: true

# Accord without Rails. The core gem has no Rails/ActiveSupport dependency — a
# schema is plain Ruby, so you can parse-and-validate anywhere: a Sinatra/Roda/
# Hanami/Grape route, a Rack app, a background job, a service object, a CLI. Run:
#
#   ruby examples/standalone.rb

require_relative "../lib/accord"

class Signup < Accord::Schema
  string   :name, :required
  email    :email, :required          # semantic type: validates + canonicalizes
  currency :amount, :positive
end

# A framework-agnostic handler: hand it request params (a Hash), get back a
# status + body. The shape is identical whether you call it from a Sinatra block,
# a Rack app, or a Sidekiq worker — Accord only cares about the Hash.
def handle(params)
  signup = Signup.parse!(params)            # a typed Signup, or raises Accord::InvalidInput
  [201, signup.dump]                        # canonical external form (strings), ready to serialize
rescue Accord::InvalidInput => e
  [422, { errors: e.errors.map(&:to_h) }]   # structured errors — render however your API needs
end

# Valid — string keys, "$"/commas stripped, email lowercased, amount a BigDecimal:
p handle({ "name" => "Ada", "email" => "Ada@Example.com", "amount" => "$1,049.99" })
# => [201, {name: "Ada", email: "ada@example.com", amount: "1049.99"}]

# Invalid — every problem reported in one pass, as data:
p handle({ "email" => "nope", "amount" => "-5" })
# => [422, {errors: [{path: [:name], ...}, {path: [:email], ...}, {path: [:amount], ...}]}]

# Or use a single type directly, no schema — one-off coercion + canonicalization:
money = Accord::Types::Currency.new
p money.parse("$1,234.50")            # => 0.12345e4  (BigDecimal; permissive parse -> nil if unparseable)
p money.dump(BigDecimal("1234.5"))    # => "1234.50"   (canonical external form)

# A bare type has no valid?/errors (those are schema features). It fails via a
# nil (permissive) or a structured CoercionError (strict):
begin
  money.parse!("nonsense")
rescue Accord::CoercionError => e
  p [e.code, e.input]                 # => [:invalid_currency, "nonsense"]
end
