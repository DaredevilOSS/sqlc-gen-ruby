# Options

All options go in the `options:` of a `codegen:` entry in `sqlc.yaml`:

```yaml
codegen:
  - plugin: ruby
    out: app/db
    options:
      driver: pg
      rubyVersion: "3.3"
      moduleName: MyApp::Db
```

Unknown or misspelled options are errors, with a hint for near misses (`generate_types` → `generateTypes`).
Options shared by several `sql:` blocks can go in the top-level `options:` of `sqlc.yaml` under the plugin's name
(`options: {ruby: {moduleName: MyApp::Db}}`); a codegen entry's own options win, and the `overrides` of both apply.

| Option | Default | What it does |
|---|---|---|
| `driver` | required | `pg`, `mysql2` or `sqlite3`. Must match the sqlc `engine:`. |
| `rubyVersion` | `3.3` | Oldest Ruby the code must run on, `3.1` – `4.0`. Rows are `Data` classes from 3.2 and `Struct`s below; `3` means any 3.x, so it gets what Ruby 3.1 needs (`Struct`s, the Timeout handling below 3.3). |
| `generateTypes` | `true` | Also generate `.rbs` type signatures. |
| `generateGemfile` | `false` | Also generate a `Gemfile` with the gems the code needs. |
| `moduleName` | `<Driver>Codegen` | The module the code lives in, e.g. `MyApp::Db`. |
| `overrides` | none | Change the type of columns / parameters, see [Overrides](#overrides). |
| `rename` | none | Rename tables (model class) and columns (attribute), e.g. `{authors: Writer, bio: biography}`; `schema.table` works too. |
| `exactTableNames` | `false` | Keep table names as model names (`authors` → `Authors`) instead of singularizing them (`Author`). |
| `preparedStatements` | `true` | `pg` only (an error with other drivers). See [below](#preparedstatements-pg). |

## `preparedStatements` (pg)

`false` sends the SQL with every call instead of preparing it (needed behind pgbouncer in transaction mode).

With the default (`true`):

* Statements dropped by `DEALLOCATE ALL` / `DISCARD ALL`, and statements PostgreSQL refuses after a migration changed
  the type of a column they return (`PG::FeatureNotSupported`: cached plan must not change result type), are prepared
  again by their next call outside a transaction. Inside a transaction, that call raises and the transaction rolls
  back; the next call prepares the statement again.
* Statements are named `Module::Class#method` (with a hash when longer than PostgreSQL's 63 bytes), so classes sharing
  a pool never run each other's SQL.

## Overrides

```yaml
overrides:
  - column: "GetAuthor:bio"          # one column of one query (<query>:<column>)
    ruby_type: { type: "Symbol", notNull: true }
  - column: "authors.bio"            # a table column, in its model and in every query (<schema>.<table>.<column> too)
    ruby_type: { type: "Symbol" }
  - column: "*:bio"                  # a column name in every query and model
    ruby_type: { type: "Pathname", notNull: false }
  - db_type: "uuid"                  # a database type, everywhere (also the elements of uuid[] arrays)
    ruby_type: { type: "String" }
```

The first match wins in this order: `<query>:<column>`, `<table>.<column>`, `*:<column>`, `db_type`.
Overrides only change the RBS types; the values are whatever the driver returns. Unknown keys are errors.
