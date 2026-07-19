###  v0.1.0  (unreleased)
- core types: string, boolean, integer, date, decimal
- semantic types: uuid, iso_currency, currency, duration, percentage
- composite money type (optional `money` gem)
- nested schemas: object, array — composed error paths
- permissive / strict parsing, canonical `dump`
- declarative validation framework + validator registry
- structured errors
- Rails integration (opt-in): `accord` controller macro, ActiveSupport notifications
- typing projections: `Schema.rbs` / `Schema.rbi` + Tapioca DSL compiler
