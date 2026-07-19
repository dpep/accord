# frozen_string_literal: true

# Accord + RABL: the realistic split. Accord parses untrusted input into typed,
# scale-controlled values; your domain logic computes a result (the amount owed
# stays a Money); RABL serializes that result. Run it directly:
#
#   ruby examples/rabl.rb
#
# No rabl gem required — the RABL template is printed as-is, and we show the
# output it would produce from the computed result.

require_relative "../lib/accord"
Accord.require_money!

RATE_SCALE = 2    # dollars-and-cents hourly rate
HOURS_SCALE = 3   # hours worked, to the thousandth

# --- 1. Parse untrusted input -----------------------------------------------
# A timesheet submission: an hourly rate and hours worked, each with its own
# decimal scale (excess precision is rejected, not silently rounded).
class Timesheet < Accord::Schema
  decimal :rate,  :positive, scale: RATE_SCALE,  required: true   # -> BigDecimal
  decimal :hours, :positive, scale: HOURS_SCALE, required: true   # -> BigDecimal
  date    :period_start, :required
  date    :period_end, :required
end

input = Timesheet.parse({
  rate: "45.50",             # scale 2
  hours: "80.125",           # scale 3 — 80 hours, 7.5 minutes
  period_start: "2026-07-01",
  period_end: "2026-07-14",
})

# --- 2. Domain logic: compute the result ------------------------------------
# rate * hours is a BigDecimal (exact); the amount owed is a Money, which
# enforces its own currency scale (USD -> 2), so the payout rounds to cents.
Paycheck = Struct.new(:period_start, :period_end, :rate, :hours, :gross_pay, keyword_init: true)

paycheck = Paycheck.new(
  period_start: input.period_start,
  period_end: input.period_end,
  rate: input.rate,
  hours: input.hours,
  gross_pay: Money.from_amount(input.rate * input.hours, "USD"),   # 45.50 * 80.125 = 3645.6875 -> $3,645.69
)

def section(title)
  puts "\n== #{title} =="
end

section "Computed result (types retained)"
puts "rate       #{paycheck.rate.inspect}       (#{paycheck.rate.class})"
puts "hours      #{paycheck.hours.inspect}   (#{paycheck.hours.class})"
puts "gross_pay  #{paycheck.gross_pay.inspect}   (#{paycheck.gross_pay.class})"

# --- 3. Serialize the result with RABL --------------------------------------
# RABL renders the Paycheck — not the input. Each value renders at its scale:
# the decimals via "%.<scale>f" (mirroring the schema), the Money via #format.
section "The RABL template you'd write (app/views/paychecks/show.rabl)"
puts <<~RABL
  object @paycheck
  attributes :period_start, :period_end
  node(:rate)      { |p| "%.#{RATE_SCALE}f" % p.rate }
  node(:hours)     { |p| "%.#{HOURS_SCALE}f" % p.hours }
  node(:gross_pay) { |p| p.gross_pay.format }
RABL

section "What that template produces"
rendered = {
  period_start: paycheck.period_start.iso8601,
  period_end: paycheck.period_end.iso8601,
  rate: format("%.#{RATE_SCALE}f", paycheck.rate),          # "45.50"
  hours: format("%.#{HOURS_SCALE}f", paycheck.hours),       # "80.125"
  gross_pay: paycheck.gross_pay.format,                     # "$3,645.69"
}
require "json"
puts JSON.pretty_generate(rendered)

# --- Aside: echoing the input back ------------------------------------------
# If you ever do want to serialize the submission verbatim (a confirmation
# echo), Schema#dump gives its canonical external form — scales applied — in one
# call, no template.
section "Aside: input.dump (canonical echo — scales applied)"
puts JSON.pretty_generate(input.dump)
