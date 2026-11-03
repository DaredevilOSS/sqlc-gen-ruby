[![Build](https://github.com/DaredevilOSS/sqlc-gen-ruby/actions/workflows/build.yml/badge.svg?branch=main)](https://github.com/DaredevilOSS/sqlc-gen-ruby/actions/workflows/build.yml)
[![Tests](https://github.com/DaredevilOSS/sqlc-gen-ruby/actions/workflows/tests.yml/badge.svg?branch=main)](https://github.com/DaredevilOSS/sqlc-gen-ruby/actions/workflows/tests.yml)

# sqlc-gen-ruby
A [sqlc](https://sqlc.dev) plugin that turns your SQL into Ruby methods, with RBS type signatures.
Works with `pg` (PostgreSQL), `mysql2` (MySQL) and `sqlite3` (SQLite), and Ruby 3.1 – 4.0.

The plugin is written in pure Ruby and ships as one self-contained WebAssembly file
(the [ruby.wasm](https://github.com/ruby/ruby.wasm) interpreter with the plugin inside), so you don't need to install anything besides sqlc.

## Quick start
**1. Point sqlc at the plugin** (`sqlc.yaml`; the URL and sha256 of each version are in its [release notes](https://github.com/DaredevilOSS/sqlc-gen-ruby/releases)):
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

**2. Write queries** (`db/query.sql`):
```sql
-- name: GetAuthor :one
SELECT * FROM authors WHERE id = $1;

-- name: CreateAuthor :one
INSERT INTO authors (name, bio) VALUES ($1, $2) RETURNING *;
```

**3. Run `sqlc generate` and use the code:**
```ruby
require_relative 'app/db/query_sql'

queries = PgCodegen::QuerySql.connect({ dbname: 'app', host: 'localhost' }, size: 5)  # a connection pool

author = queries.create_author(name: 'Seuss', bio: nil)  # => #<data CreateAuthorRow id=1, name="Seuss", bio=nil>
queries.get_author(id: author.id)                         # the row, or nil
queries.get_author!(id: 42)                               # raises QuerySql::NotFound instead of returning nil

queries.transaction do |tx|                               # COMMIT when the block ends, ROLLBACK if it raises
  tx.create_author(name: 'a', bio: nil)
end
```
More: [the generated code for every driver](docs/Examples.md) (it is the plugin's real output, from
[these schemas and queries](examples/authors)).

## Options
| Option | Default | What it does |
|---|---|---|
| `driver` | required | `pg`, `mysql2` or `sqlite3`. Must match the sqlc `engine:`. |
| `rubyVersion` | `3.3` | Oldest Ruby the code must run on, `3.1` – `4.0`. Rows are `Data` classes from 3.2 and `Struct`s below. |
| `generateTypes` | `true` | Also generate `.rbs` type signatures. |
| `generateGemfile` | `false` | Also generate a `Gemfile` with the gems the code needs. |
| `moduleName` | `<Driver>Codegen` | The module the code lives in, e.g. `MyApp::Db`. |
| `overrides` | none | Change the type of columns / parameters, see [below](#overrides). |
| `rename` | none | Rename tables (model class) and columns (attribute), e.g. `{authors: Writer, bio: biography}`; `schema.table` works too. |
| `exactTableNames` | `false` | Keep table names as model names (`authors` → `Authors`) instead of singularizing them (`Author`). |
| `preparedStatements` | `true` | `pg` only (an error with other drivers). `false` sends the SQL with every call instead of preparing it (needed behind pgbouncer in transaction mode). |

Unknown or misspelled options are errors, with a hint for near misses (`generate_types` → `generateTypes`).
Options shared by several `sql:` blocks can go in the top-level `options:` of `sqlc.yaml` under the plugin's name
(`options: {ruby: {moduleName: MyApp::Db}}`); a codegen entry's own options win, and the `overrides` of both apply.

### Overrides
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

## The generated code
For each query file you get `query_sql.rb` with a `QuerySql` class (one method per query), plus `models.rb` (one class
per table, one module of constants per enum), `connection.rb` (shared helpers) and the matching `.rbs` files.

* **Arguments** are keywords named after the parameters (`get_author(id:)`); `sqlc.arg(name)` names them yourself.
  Missing or unknown ones raise `ArgumentError`. Nullable parameters named with `sqlc.arg` / `sqlc.narg` default
  to `nil`; other nullable parameters (`VALUES ($1, $2)`) must be passed, even as `nil`.
* **Rows** are frozen `Data` objects from Ruby 3.2 (with `with` and `to_h`) or mutable keyword `Struct`s below Ruby 3.2;
  both support pattern matching: `case row in { id:, name: }`.
* **Bang finders:** every `:one` query also gets a `get_author!` that raises `QuerySql::NotFound` instead of returning `nil`.
* **Connections:** `QuerySql.connect(params, **pool_options)` builds a [`connection_pool`](https://github.com/mperham/connection_pool).
  To use a pool you already have (or a fake in tests) pass it to `QuerySql.new(pool)`; anything with `#with` works.
  For SQLite pass a `SQLite3::Database` (opened with any options, `results_as_hash: true` included): `QuerySql.new(db)`.
* **Logging:** `connect(params, logger: Rails.logger)` / `new(pool, logger:)` logs `QuerySql#get_author (0.4ms)` at
  debug level for each query and transaction. Parameter values are never logged.
* **Async / fibers:** it is plain synchronous Ruby and works with the Fiber scheduler ([`async`](https://github.com/socketry/async)):
  inside `Sync { ... }`, pooled `pg` and `mysql2` queries run concurrently (`mysql2` blocks the thread on Windows). MySQL parameters are quoted client-side
  with `Mysql2::Client#escape` and sent with `Client#query`, not server-side prepared statements. SQLite queries run
  one at a time.
* **Style:** SQL lives in frozen heredoc constants (`GET_AUTHOR_SQL`), comments above a query become its doc comment,
  table / column / enum comments of the schema become doc comments of the models. The code is RuboCop-clean; where a
  name from your schema breaks a RuboCop naming rule (`"UserId"`, `naïve`), that class or method gets a `rubocop:disable`.
  A result column without a usable name (`SELECT 1, now()`) is named by its position: `column_1`, `column_2`, ...

### Transactions
```ruby
queries.transaction(isolation: :serializable) do |tx|
  id = tx.create_author_return_id(name: 'a', bio: nil)
  tx.transaction { tx.create_book(name: 'b', author_id: id) }  # nested: a SAVEPOINT
  :done                                                         # the block's value is returned
end
```
* Everything in the block runs on one connection. It commits when the block ends (also on `break`, `return`, `throw`)
  and rolls back when it raises or the thread is killed. On Ruby <3.3 with timeout <0.4, `break`, `return`, and
  `throw` also roll back because Timeout cannot be told apart; add `gem 'timeout', '>= 0.4'` to the generated Gemfile
  to keep those exits committing. A nested `transaction` rolls back only its own part. With `connection_pool` or
  SQLite, parent-object calls from the same thread reuse the transaction connection; injected `#with` objects must do
  the same.
* `isolation:` (`pg`, `mysql2`) takes `:read_uncommitted`, `:read_committed`, `:repeatable_read`, `:serializable`;
  `mode:` (`sqlite3`) takes `:deferred`, `:immediate`, `:exclusive`. Other values raise before anything runs, and so
  do `isolation:` / `mode:` on a nested `transaction` (a savepoint cannot change them).
* PostgreSQL: if a statement fails and the block rescues the error, PostgreSQL still rolls the whole transaction
  back, so `transaction` raises `PG::InFailedSqlTransaction` instead of pretending it committed. In a nested
  `transaction` only the savepoint is rolled back: the outer block can rescue that error and go on.
* A connection the server closed (restart, failover, killed backend) is reconnected (`pg`) or replaced in the pool
  (`mysql2`) the next time it is checked out; the call that hit the dead connection still raises. Inside `transaction`
  a lost `pg` connection is not reconnected: every later call in the block and `transaction` itself raise
  `PG::ConnectionBad`, so nothing after the loss runs outside the transaction (the server rolled it back). A `mysql2`
  client that mysql2 closed because a running query was interrupted (an `Async` task stopped, `Thread#raise`) is
  replaced the same way, without failing the next call.
* SQLite: threads and fibers sharing one `SQLite3::Database` take turns; a transaction holds the database until it ends.

## Supported features
### Query annotations
| Annotation | Returns | Notes |
|---|---|---|
| `:one` | the row or `nil` | plus a bang finder (`get_author!`) |
| `:many` | `Array` of rows | |
| `:exec` | `nil` | |
| `:execrows` | number of affected rows | |
| `:execlastid` | the new id | PostgreSQL / SQLite: needs `RETURNING id`; MySQL: the auto-increment id |
| `:execresult` | `ExecResult` (`rows_affected`, `last_insert_id`) | `last_insert_id` is `nil` on PostgreSQL (use `RETURNING`) |
| `:batchexec` / `:batchone` / `:batchmany` | `nil` / `Array` of rows or `nil` / `Array` of `Array`s of rows | take an `Array` of `<Query>Args` and run the query once per element, on one connection |
| `:copyfrom` | `nil` | bulk insert of an `Array` of `<Query>Args`; all rows or none (see below) |

`:copyfrom` uses `COPY ... FROM STDIN` on PostgreSQL and batched multi-row `INSERT`s on SQLite. On MySQL it uses
`LOAD DATA LOCAL INFILE`, which needs `local_infile: true` in the `Mysql2::Client` params and `local_infile=1` on the
server; duplicate keys and invalid values raise `Mysql2::Error` instead of being skipped. Conflict clauses are kept:
`INSERT OR REPLACE` / `OR IGNORE` / `ON CONFLICT ... DO ...` on SQLite, `INSERT IGNORE` (duplicates skipped) and
`REPLACE` on MySQL. Clauses `COPY` / `LOAD DATA` cannot express (`ON CONFLICT` / `RETURNING` on PostgreSQL,
`ON DUPLICATE KEY UPDATE` on MySQL) are generation errors; use `:batchexec` for those.
* MySQL: `LOAD DATA` commits an open transaction that was started with raw SQL (`BEGIN`); call `:copyfrom` inside
  `transaction` instead.

### Macros
| Macro | PostgreSQL | MySQL | SQLite | Notes |
|---|:---:|:---:|:---:|---|
| `sqlc.arg` | ✅ | ✅ | ✅ | names a parameter (unnamed ones such as `ANY($1::BIGINT[])` become `param1`, ...) |
| `sqlc.narg` | ✅ | ✅ | ✅ | a nullable parameter (`T?`, defaults to `nil`) |
| `sqlc.slice` | 🚫 | ✅ | ✅ | `IN (sqlc.slice(ids))` takes an `Array` (an empty one: `IN` matches nothing, `NOT IN` everything). PostgreSQL: use `= ANY($1::bigint[])` with an array |
| `sqlc.embed` | ✅ | ✅ | ✅ | the row gets an attribute holding the table's model (`author`, `author2` for the same table twice); `nil` when an outer join found no row |

🚫 = not offered by sqlc for that database.

### Types
* Types follow what the drivers return: `Integer`, `Float`, `BigDecimal` (`numeric` / `decimal`), `String`, `Date`, `Time`,
  `IPAddr`, `true` / `false`; `json` / `jsonb` are parsed (`untyped`); nullable columns and parameters are `T?`.
* PostgreSQL arrays are `Array[T]` (`Array[Array[T]]` for `T[][]`); arrays of types the pg gem does not decode
  (`uuid[]`, enum arrays, ...) are `Array[String]`. Geometric, range, full-text, `hstore`, `ltree`, `timetz`, `reg*` and
  composite types are `String`s; domains and unknown types are `untyped`.
* Enums are `String`s, with constants in `models.rb` (`ExtendedBioType::MEMOIR`, `ExtendedBioType::ALL`).
* SQLite follows its [type affinity rules](https://www.sqlite.org/datatype3.html#determination_of_column_affinity)
  (`VARCHAR(255)` → `String`, `DECIMAL(10,5)` → `Float`, `UNSIGNED BIG INT` → `Integer`); `JSON` and `UUID` columns are `String`s.
  The generated SQLite code uses `Monitor`: if you run Steep, add `library "monitor"` to your `Steepfile`.

### Names
* Query methods and keyword arguments are snake_cased, with acronyms kept together (`MIN_ID` → `min_id`,
  `HTTPServer` → `http_server`); Ruby keywords get a trailing `_` (`end_:`). Row members use the column spelling
  reported by sqlc for the engine, except names that conflict with generated row methods (`class_`, `hash_`):
  PostgreSQL and SQLite keep `"camelCase"` as `:camelCase`, while MySQL reports it as `:camelcase`. A column named
  `end` is the row member `:end` but the argument `end_:`.
* A parameter used twice is one keyword when named with `sqlc.arg`; repeated `?` / `$n` of one column become `id:`, `id_2:`.
* A table `authors` next to a table `author` keeps its plural model name (`Authors`). Query names that would replace
  a generated method (`Transaction`, `Initialize`, ...) are errors.

### Limitations
* Two result columns with the same name (e.g. `a.id, b.id`) are an error: alias one (`b.id AS book_id`) or use `sqlc.embed`.
* SQLite's `NUMERIC` affinity can return an `Integer` where `Float` is declared.
* `:batchexec` / `:batchone` / `:batchmany` are not atomic on their own: wrap them in `transaction` for all-or-nothing.
* SQLite: sqlc does not see parameters in `ON CONFLICT ... DO UPDATE SET` (it leaves `sqlc.arg(...)` in the SQL or
  reports fewer parameters than there are `?`), so such queries are generation errors. Use `excluded.<column>`
  (`DO UPDATE SET n = counters.n + excluded.n`) or move the value into `VALUES`.
* SQLite transactions belong to the thread that opened them; fibers sharing the same database take turns, and a
  transaction holds it until it ends.
* Not applicable to Ruby (they exist in the C# plugin): `withAsyncSuffix` / `withCancellationToken` (use the Fiber
  scheduler), `useDapper`, target framework / csproj options (`moduleName` replaces the namespace).

# Contributing
You need Ruby 3.3 (`bundle install`), [sqlc](https://docs.sqlc.dev/en/latest/overview/install.html) (version in
[`scripts/tool-versions.env`](scripts/tool-versions.env)), `curl` + `tar` to build the WASM, and PostgreSQL / MySQL
servers (or Docker) for the end-to-end tests.

```
bundle exec rake test                 # unit + golden tests (no database needed)
bundle exec rake rubocop steep        # the generated code must stay RuboCop- and Steep-clean
rake sqlc_generate_process            # regenerate examples/ with exe/plugin.rb
rake sqlc_generate_wasm               # build dist/plugin.wasm, then regenerate examples/ with it
rake end2end_sqlite3                  # end-to-end, no server needed
rake end2end_pg end2end_mysql2        # end-to-end, needs servers (see docs/Testing.md)
rake run_end2end_tests                # all of it in Docker (docker-compose)
```
`examples/` is the plugin's committed output and CI fails when it drifts, so regenerate it with every change to the
generated code. Pull requests need both CI workflows (`build.yml`, `tests.yml`) green.

Releases are started by a maintainer (**Actions → Release → Run workflow**) and are automated from there: the full
test gate, the tag, the GitHub release with the tested `sqlc-gen-ruby.wasm` and its sha256, and a check of the published file.

| Doc | What |
|---|---|
| [docs/Architecture.md](docs/Architecture.md) | how the generator works, where to change what, adding a feature / driver / option |
| [docs/Testing.md](docs/Testing.md) | the test layers, CI workflows, what to run before pushing |
| [docs/Releasing.md](docs/Releasing.md) | the release process and versioning rules |
| [docs/Design.md](docs/Design.md) | the WASM packaging and design decisions |
| [docs/Examples.md](docs/Examples.md) | per-driver configs and links to the generated examples |
| [CLAUDE.md](CLAUDE.md) | the same orientation condensed for AI coding assistants |
