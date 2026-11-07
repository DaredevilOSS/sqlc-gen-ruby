<h1 align="center">sqlc-gen-ruby</h1>

<p align="center">
  <b>Write SQL. Get typed, idiomatic Ruby.</b><br>
  A <a href="https://sqlc.dev">sqlc</a> plugin for PostgreSQL, MySQL and SQLite, with RBS signatures.
</p>

<p align="center">
  <a href="https://github.com/DaredevilOSS/sqlc-gen-ruby/actions/workflows/build.yml"><img alt="Build" src="https://github.com/DaredevilOSS/sqlc-gen-ruby/actions/workflows/build.yml/badge.svg?branch=main"></a>
  <a href="https://github.com/DaredevilOSS/sqlc-gen-ruby/actions/workflows/tests.yml"><img alt="Tests" src="https://github.com/DaredevilOSS/sqlc-gen-ruby/actions/workflows/tests.yml/badge.svg?branch=main"></a>
</p>

---

## How it works

**1. You write SQL**

```sql
-- schema.sql
CREATE TABLE authors (
  id   BIGSERIAL PRIMARY KEY,
  name text NOT NULL,
  bio  text
);

-- query.sql
-- name: GetAuthor :one
-- Returns the author with the given id, or nil when there is none.
SELECT * FROM authors WHERE id = $1 LIMIT 1;

-- name: CreateAuthor :one
INSERT INTO authors (name, bio) VALUES ($1, $2) RETURNING *;
```

**2. `sqlc generate` writes Ruby, and RBS to go with it**

```ruby
# Returns the author with the given id, or nil when there is none.
def get_author(id:)
  ...
end
```
```rbs
def get_author: (id: ::Integer) -> GetAuthorRow?
def get_author!: (id: ::Integer) -> GetAuthorRow
class GetAuthorRow
  attr_reader id: ::Integer
  attr_reader name: ::String
  attr_reader bio: ::String?
end
```

**3. You call it**

```ruby
queries = PgCodegen::QuerySql.connect({ dbname: 'app', host: 'localhost' }, size: 5)   # a connection pool

author = queries.create_author(name: 'Seuss', bio: nil)   # => #<data CreateAuthorRow id=1, name="Seuss", bio=nil>
queries.get_author(id: author.id)                          # the row, or nil
queries.get_author!(id: 42)                                # raises QuerySql::NotFound

queries.transaction do |tx|                                # COMMIT at the end, ROLLBACK if it raises
  tx.create_author(name: 'a', bio: nil)
end
```

No ORM and no runtime dependency on the plugin: you get plain Ruby files that are committed and reviewable, in the
style you would have written by hand (keyword arguments, `Data` rows, pattern matching, RuboCop- and Steep-clean).
See the [full generated output](docs/Examples.md) for every driver.

## Install

The plugin is one WebAssembly file ([ruby.wasm](https://github.com/ruby/ruby.wasm) with the plugin inside): the only
thing to install is [sqlc](https://docs.sqlc.dev/en/latest/overview/install.html). Add it to `sqlc.yaml` (the URL and
sha256 of every version are in its [release notes](https://github.com/DaredevilOSS/sqlc-gen-ruby/releases)):

```yaml
version: "2"
plugins:
- name: ruby
  wasm:
    url: https://github.com/DaredevilOSS/sqlc-gen-ruby/releases/download/${RELEASE_TAG}/sqlc-gen-ruby.wasm
    sha256: ${RELEASE_SHA}
sql:
  - schema: "db/schema.sql"
    queries: "db/query.sql"
    engine: "postgresql"        # or "mysql" / "sqlite"
    codegen:
      - plugin: ruby
        out: app/db
        options:
          driver: pg            # or mysql2 / sqlite3
```

Run `sqlc generate`, add `connection_pool` and your driver gem (`pg`, `mysql2` or `sqlite3`) to your Gemfile (or set
`generateGemfile: true` and the plugin writes one), and `require_relative 'app/db/query_sql'`.

## What's supported

Ruby 3.1 – 4.0 · PostgreSQL (`pg`) · MySQL (`mysql2`) · SQLite (`sqlite3`)

### Query annotations

| Annotation | Returns | PostgreSQL | MySQL | SQLite |
|---|---|:---:|:---:|:---:|
| `:one` | the row or `nil`, plus a bang finder (`get_author!`) | ✅ | ✅ | ✅ |
| `:many` | an `Array` of rows | ✅ | ✅ | ✅ |
| `:exec` | `nil` | ✅ | ✅ | ✅ |
| `:execrows` | number of affected rows | ✅ | ✅ | ✅ |
| `:execlastid` | the new id | ✅ | ✅ | ✅ |
| `:execresult` | `ExecResult` (`rows_affected`, `last_insert_id`) | ✅ | ✅ | ✅ |
| `:batchexec` `:batchone` `:batchmany` | run the query for every element of an `Array`, on one connection | ✅ | ✅ | ✅ |
| `:copyfrom` | bulk insert of an `Array` or any `Enumerable` | ✅ `COPY` | ✅ `LOAD DATA` | ✅ multi-row `INSERT` |

### sqlc macros

| Macro | PostgreSQL | MySQL | SQLite |
|---|:---:|:---:|:---:|
| `sqlc.arg(name)`: name a parameter | ✅ | ✅ | ✅ |
| `sqlc.narg(name)`: nullable, defaults to `nil` | ✅ | ✅ | ✅ |
| `sqlc.slice(ids)`: `IN (...)` with an `Array` | `= ANY($1::bigint[])` | ✅ | ✅ |
| `sqlc.embed(table)`: the row holds the table's model | ✅ | ✅ | ✅ |

### Types

| SQL | Ruby |
|---|---|
| integers, floats | `Integer`, `Float` |
| `numeric`, `decimal` | `BigDecimal` |
| text, `varchar` | `String` |
| enums | `String`, plus constants (`ExtendedBioType::MEMOIR`, `ExtendedBioType::ALL`) |
| `date`, `timestamp`, `timestamptz`, `datetime` | `Date`, `Time` |
| `inet`, `cidr` | `IPAddr` |
| `json`, `jsonb` | parsed Ruby objects on PostgreSQL, JSON text on MySQL |
| arrays (PostgreSQL) | `Array[T]` |
| nullable columns and parameters | `T?` |

Types follow what each driver returns; override any of them with [`overrides`](docs/Options.md#overrides).
Everything else (ranges, geometric types, composite types, SQLite affinity, time zones): [Types and names](docs/Types.md).

### Built for production

| | |
|---|---|
| **Transactions** | `transaction` with commit/rollback, nested savepoints and isolation levels (`isolation:` / `mode:`) |
| **Pooling** | `connection_pool` built for you, or bring your own pool, `SQLite3::Database` or a shared ActiveRecord / Sequel connection |
| **Resilience** | `Timeout`, `Thread#kill`, stopped `Async` tasks, lost connections, deadlocks and forked workers (Puma, Sidekiq) are handled |
| **Concurrency** | plain Ruby that works with the Fiber scheduler (`async`) |
| **Logging** | `connect(params, logger: Rails.logger)` logs `QuerySql#get_author (0.4ms)`; parameter values are never logged |
| **Docs and types** | SQL comments become doc comments; `.rbs` for every model, row and method |

Details: [Transactions and connections](docs/Transactions.md) · [Generated code](docs/Generated-Code.md) · [Queries](docs/Queries.md).

## Options

Set them under `options:` of the `codegen` entry.

| Option | Default | What it does |
|---|---|---|
| `driver` | required | `pg`, `mysql2` or `sqlite3`; must match the sqlc `engine:` |
| `rubyVersion` | `3.3` | oldest Ruby the code must run on (`3.1` – `4.0`); `Data` rows from 3.2, `Struct` below |
| `generateTypes` | `true` | also generate `.rbs` signatures |
| `generateGemfile` | `false` | also generate a `Gemfile` |
| `moduleName` | `<Driver>Codegen` | the module the code lives in, e.g. `MyApp::Db` |
| `overrides` | none | change the Ruby type of columns / parameters |
| `rename` | none | rename tables and columns, e.g. `{authors: Writer, bio: biography}` |
| `exactTableNames` | `false` | keep `authors` as `Authors` instead of singularizing to `Author` |
| `preparedStatements` | `true` | `pg` only; `false` for pgbouncer in transaction mode |

Misspelled options are errors with a "did you mean" hint. Everything about them, including sharing options between
`sql:` blocks: [Options](docs/Options.md).

## Documentation

| | |
|---|---|
| [Generated code](docs/Generated-Code.md) | files, rows, finders, logging, style |
| [Queries](docs/Queries.md) | annotations, `:copyfrom`, macros, arguments |
| [Transactions and connections](docs/Transactions.md) | transactions, pools, forks, Async, shared connections |
| [Types and names](docs/Types.md) | type mapping, time zones, enums, naming rules |
| [Options](docs/Options.md) | every option and `overrides` |
| [Troubleshooting](docs/Troubleshooting.md) | "I got this error / this looks odd": causes and fixes, per database |
| [Examples](docs/Examples.md) | per-driver configs and generated output |

## Contributing

Contributions are welcome: see [Contributing](docs/Contributing.md) for the setup, the test commands and the release
process, and [Architecture](docs/Architecture.md) for how the generator works.
