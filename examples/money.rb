# frozen_string_literal: true

# The money composite type — amount + currency parsed into a money-gem Money
# value. Needs the `money` gem (Accord lazy-requires it). Run it directly:
#
#   ruby examples/money.rb

require_relative "../lib/accord"

# A default currency makes money polymorphic: a bare amount is USD, an explicit
# currency overrides.
Accord.configure { |c| c.default_currency = "USD" }

class Payroll < Accord::Schema
  money :salary                          # nested { amount:, currency: }
  money :bonus,   format: :flat          # sibling keys: bonus + bonus_currency
  money :stipend, currency: "USD"        # currency locked, input ignored
end

def section(title) = puts("\n== #{title} ==")

section "Nested, flat, and default/override currency"

input = Payroll.parse({
  salary: { amount: "65000.00", currency: "eur" },   # explicit currency, canonicalized
  bonus: "5000.00",                                   # flat amount -> default USD
  bonus_currency: "GBP",                              # ...overridden to GBP
  stipend: { amount: "1000.00" },                     # currency locked to USD
})

puts "valid?   #{input.valid?}"
puts "salary   #{input.salary}"
puts "bonus    #{input.bonus}"
puts "stipend  #{input.stipend}"

section "Currency-aware precision (JPY has no minor units)"

bad = Payroll.parse({ salary: { amount: "100.5", currency: "JPY" } })
bad.errors.each { |e| puts "  #{e.to_h}" }

section "dump — canonical nested form regardless of input format"

field = Payroll.fields[:bonus]     # declared flat, still dumps nested
puts field.dump(input.bonus).inspect
