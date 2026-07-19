# Typing (Sorbet & Steep)

A schema's field readers are defined dynamically (`define_method`), so a type checker can't see `input.salary : BigDecimal` on its own. Because every field already knows its internal type, Accord **projects** that knowledge into type signatures — the same pattern as OpenAPI, and with no runtime dependency (it only emits signatures).

- **Steep** consumes RBS — use `Schema.rbs`.
- **Sorbet** consumes RBI — use the bundled Tapioca compiler (or `Schema.rbi`).

## The type mapping

| Field | RBS / Sorbet type |
|---|---|
| `string` / `uuid` / `iso_currency` | `String` |
| `boolean` | `bool` / `T::Boolean` |
| `integer` | `Integer` |
| `date` | `Date` |
| `decimal` / `currency` / `duration` / `percentage` | `BigDecimal` |
| `object :x, Address` | `Address` |
| `array :x, Employee` | `Array[Employee]` / `T::Array[Employee]` |
| `money` | `Money` |

**Nilability follows the valid-shape contract:** required and defaulted fields are non-nilable; optional fields are nilable (`String?` in RBS, `T.nilable(String)` in Sorbet). You read accessors after checking `valid?`, so this types the happy path.

## Steep / RBS

`Schema.rbs` returns an RBS class declaration:

```ruby
CreateEmployee.rbs
# class CreateEmployee < Accord::Schema
#   def name: () -> String
#   def active: () -> bool
#   def salary: () -> BigDecimal?
#   def address: () -> Address?
# end
```

Write each schema's RBS into `sig/` and Steep type-checks against it. A rake task keeps them fresh:

```ruby
# lib/tasks/accord.rake
task :accord_sigs do
  [CreateEmployee, Address, Payroll].each do |schema|
    File.write("sig/schemas/#{schema.name.gsub("::", "_").downcase}.rbs", schema.rbs)
  end
end
```

`BigDecimal`/`Date` are stdlib (RBS ships them); `Money` needs the money gem's RBS via `rbs collection`; each nested schema gets its own `.rbs`.

## Sorbet / RBI — via Tapioca (recommended)

Accord ships a **Tapioca DSL compiler** at `lib/tapioca/dsl/compilers/accord_schema.rb`. In a project that uses `tapioca`, it's auto-discovered — running

```sh
bundle exec tapioca dsl
```

generates RBI for every `Accord::Schema` subclass into `sorbet/rbi/dsl/`, so Sorbet knows each reader's return type. It also types the `parse`/`parse!` entry points as the schema (`CreateEmployee.parse!(params)` → `CreateEmployee`, no `T.let`). No manual conversion, no drift — the compiler reuses the exact same type mapping as `Schema.rbs`. The file is inert unless Tapioca is present, so shipping it adds no dependency.

A second compiler (`accord_controller.rb`) types the readers the Rails `accord` macro generates — reading each controller's `accord_inputs` registry, a schema reader becomes that schema, a `[Schema]` list reader becomes `T::Array[Element]` — so typing reaches the controller, accord's home turf.

## Sorbet / RBI — standalone

For a one-off or a non-Tapioca setup, `Schema.rbi` returns the RBI directly:

```ruby
CreateEmployee.rbi
# class CreateEmployee < Accord::Schema
#   sig { returns(String) }
#   def name; end
#
#   sig { returns(T.nilable(BigDecimal)) }
#   def salary; end
# end
```

## Anonymous schemas

`Schema.rbs` / `Schema.rbi` need a class name. Named subclasses use their own; for an anonymous schema, pass one explicitly:

```ruby
schema.rbs(class_name: "CreateEmployee")
```

## Exporting RBS to `sig/`

For RBI, Sorbet's standard flow already covers you — Accord ships a Tapioca DSL compiler, so `bundle exec tapioca dsl` writes RBI under `sorbet/rbi/dsl/`. RBS has no such generator, so Accord provides a rake task:

```sh
bundle exec rake accord:rbs            # -> sig/accord.rbs (every declared schema)
OUTPUT=sig/inputs.rbs bundle exec rake accord:rbs
```

Under Rails the task is auto-registered (it eager-loads the app first). Outside Rails, `require "accord/rake"` in your `Rakefile` and make sure your schemas are loaded. Discovery is `Accord::Schema.descendants.select(&:name)` — the same hook you can use directly to build a custom export.

Only **named** schemas are exported — a truly anonymous `Class.new(Accord::Schema)` has no name to declare, and `Schema.rbs` raises on one. This isn't a gap: inline controller inputs and `[Schema]` lists are named (the macro assigns them constants), named nested schemas each get their own declaration, and an anonymous *nested* schema is still captured — inlined by its parent in OpenAPI, or rendered `untyped` in RBS (name it to get a real reference). The task prints how many it skipped rather than dropping them silently.

---

See also: [getting_started.md](getting_started.md) · [types.md](types.md)
