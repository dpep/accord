# frozen_string_literal: true

# Accord + RABL: the realistic split. Accord parses untrusted input into typed
# values; your domain logic turns those into a result (which keeps the value
# types — a Money stays a Money); RABL serializes that result. Run it directly:
#
#   ruby examples/rabl.rb
#
# No rabl gem required — the RABL template is printed as-is, and we show the
# output it would produce from the computed result.

require_relative "../lib/accord"

# --- 1. Parse untrusted input -----------------------------------------------
# A timesheet submission: an hourly rate, hours worked, and the pay period.
class Timesheet < Accord::Schema
  money   :rate, currency: "USD", format: :flat, required: true   # -> Money
  decimal :hours, :positive, required: true                        # -> BigDecimal
  date    :period_start, :required
  date    :period_end, :required
end

input = Timesheet.parse({
  rate: "45.50",            # flat money -> Money($45.50)
  hours: "80",              # -> BigDecimal
  period_start: "2026-07-01",
  period_end: "2026-07-14",
})

# --- 2. Domain logic: compute the result ------------------------------------
# The typed values flow through the math. Money * BigDecimal is still a Money —
# no float, no precision loss — so `gross_pay` is a first-class Money object.
Paycheck = Struct.new(:period_start, :period_end, :hours, :rate, :gross_pay, keyword_init: true)

paycheck = Paycheck.new(
  period_start: input.period_start,
  period_end: input.period_end,
  hours: input.hours,
  rate: input.rate,
  gross_pay: input.rate * input.hours,   # Money
)

def section(title)
  puts "\n== #{title} =="
end

section "Computed result (types retained)"
puts "rate       #{paycheck.rate.inspect}       (#{paycheck.rate.class})"
puts "hours      #{paycheck.hours.inspect}                 (#{paycheck.hours.class})"
puts "gross_pay  #{paycheck.gross_pay.inspect}   (#{paycheck.gross_pay.class})"

# --- 3. Serialize the result with RABL --------------------------------------
# RABL renders the Paycheck — not the input. Money values render through the
# money gem (`.format` / `.amount`), dates through `.iso8601`.
section "The RABL template you'd write (app/views/paychecks/show.rabl)"
puts <<~RABL
  object @paycheck
  attributes :period_start, :period_end
  node(:hours)     { |p| p.hours.to_s("F") }
  node(:rate)      { |p| p.rate.format }
  node(:gross_pay) { |p| p.gross_pay.format }
RABL

section "What that template produces"
rendered = {
  period_start: paycheck.period_start.iso8601,
  period_end: paycheck.period_end.iso8601,
  hours: paycheck.hours.to_s("F"),
  rate: paycheck.rate.format,
  gross_pay: paycheck.gross_pay.format,
}
require "json"
puts JSON.pretty_generate(rendered)

# --- Aside: echoing the input back ------------------------------------------
# If you ever do want to serialize the input verbatim (e.g. a confirmation
# echo), Schema#dump gives its canonical external form in one call — no template.
section "Aside: input.dump (canonical echo of what was submitted)"
puts JSON.pretty_generate(input.dump)
