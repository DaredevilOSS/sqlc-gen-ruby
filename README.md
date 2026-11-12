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

[sqlc](https://sqlc.dev) reads your schema and your queries and checks them against each other. This plugin turns
the result into plain Ruby files: one method per query, one class per result row, and `.rbs` signatures for all of it.
There is no ORM and no runtime library: the generated code only needs your database gem and `connection_pool`.

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

**2. `sqlc generate` writes Ruby, and RBS to go with it** (abridged)

```ruby
# Returns the author with the given id, or nil when there is none.
def get_author(id:)
  ...
end
```
```rbs
class GetAuthorRow
  attr_reader id: ::Integer
  attr_reader name: ::String
  attr_reader bio: ::String?
end

def get_author: (id: ::Integer) -> GetAuthorRow?
def get_author!: (id: ::Integer) -> GetAuthorRow
```

**3. You call it**

```ruby
require_relative 'app/db/query_sql'

queries = PgCodegen::QuerySql.connect({ dbname: 'app', host: 'localhost' }, size: 5)   # a connection pool

author = queries.create_author(name: 'Seuss', bio: nil)   # => #<data PgCodegen::CreateAuthorRow id=1, name="Seuss", bio=nil>
queries.get_author(id: author.id)                          # the row, or nil
queries.get_author!(id: 42)                                # raises QuerySql::NotFound

queries.transaction do |tx|                                # COMMIT at the end, ROLLBACK if it raises
  tx.create_author(name: 'a', bio: nil)
end
```

The complete, committed output for every database is in [`examples/`](docs/Examples.md).

## Install

The plugin is one WebAssembly file, so the only thing to install is
[sqlc](https://docs.sqlc.dev/en/latest/overview/install.html). Add the plugin to `sqlc.yaml`; the URL and sha256 of
every version are in its [release notes](https://github.com/DaredevilOSS/sqlc-gen-ruby/releases):

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

Then:

1. run `sqlc generate`;
2. add `connection_pool` and your driver gem (`pg`, `mysql2` or `sqlite3`) to your Gemfile, or set
   `generateGemfile: true` and the plugin writes one;
3. `require_relative 'app/db/query_sql'`.

## What's supported

Ruby 3.1 – 4.0, with PostgreSQL (`pg`), MySQL (`mysql2`) and SQLite (`sqlite3`).

### Queries

Every sqlc annotation works on all three databases. Details: [Queries](docs/Queries.md).

| Annotation | The method returns |
|---|---|
| `:one` | the row or `nil`; a second method, `get_author!`, raises instead of returning `nil` |
| `:many` | an `Array` of rows |
| `:exec` | `nil` |
| `:execrows` | the number of affected rows |
| `:execlastid` | the new id |
| `:execresult` | an `ExecResult` (`rows_affected`, `last_insert_id`) |
| `:batchexec` `:batchone` `:batchmany` | runs the query once per element of an `Array`, on one connection |
| `:copyfrom` | bulk insert, all rows or none: `COPY` (PostgreSQL), `LOAD DATA` (MySQL), multi-row `INSERT` (SQLite) |

| Macro | What it does |
|---|---|
| `sqlc.arg(name)` | names a parameter |
| `sqlc.narg(name)` | names a nullable parameter, which defaults to `nil` |
| `sqlc.slice(ids)` | `IN (...)` with an `Array` (MySQL, SQLite; on PostgreSQL use `= ANY($1::bigint[])`) |
| `sqlc.embed(table)` | puts the table's model into the row |

### Types

Values are what the driver gem returns, so the Ruby type of a column depends on the database.
Details and the full list: [Types](docs/Types.md).

| SQL | PostgreSQL | MySQL | SQLite |
|---|---|---|---|
| integers | `Integer` | `Integer` | `Integer` |
| `real`, `double` | `Float` | `Float` | `Float` |
| `numeric`, `decimal` | `BigDecimal` | `BigDecimal` | `Float` |
| text, binary | `String` | `String` | `String` |
| `boolean` | `true` / `false` | `Integer` (0 / 1) | `Integer` (0 / 1) |
| `date` | `Date` | `Date` | `String` |
| `timestamp`, `datetime` | `Time` | `Time` | `String` |
| JSON | parsed Ruby objects | `String` (JSON text) | `String` (JSON text) |
| enums | `String` + constants | `String` + constants | |
| arrays | `Array[T]` | | |
| `inet`, `cidr` | `IPAddr` | | |

Nullable columns and parameters are `T?`. The declared type of any column can be changed with
[`overrides`](docs/Options.md#overrides).

### At runtime

| | |
|---|---|
| **Transactions** | `transaction` commits or rolls back, nests with savepoints and takes an isolation level. [More](docs/Transactions.md) |
| **Connections** | a `connection_pool` built for you, your own pool, or a connection shared with ActiveRecord / Sequel. [More](docs/Connections.md) |
| **Concurrency** | threads, forked workers (Puma, Sidekiq) and the Fiber scheduler (`async`). [More](docs/Connections.md#forked-processes) |
| **Failures** | timeouts, killed threads, lost connections and deadlocks never leave a connection inside a transaction. [More](docs/Transactions.md#when-something-goes-wrong) |
| **Logging** | pass `logger:` to log each query's name and duration; parameter values are never logged. [More](docs/Generated-Code.md#logging) |

## Options

Set them under `options:` of the `codegen` entry. Details: [Options](docs/Options.md).

| Option | Default | What it does |
|---|---|---|
| `driver` | required | `pg`, `mysql2` or `sqlite3`; must match the sqlc `engine:` |
| `rubyVersion` | `3.3` | the oldest Ruby the code must run on (`3.1` – `4.0`) |
| `generateTypes` | `true` | also generate `.rbs` signatures |
| `generateGemfile` | `false` | also generate a `Gemfile` |
| `moduleName` | `<Driver>Codegen` | the module the code lives in, e.g. `MyApp::Db` |
| `overrides` | none | change the declared Ruby type of columns and parameters |
| `rename` | none | rename tables and columns, e.g. `{authors: Writer, bio: biography}` |
| `exactTableNames` | `false` | name the model `Authors` instead of the singular `Author` |
| `preparedStatements` | `true` | `pg` only; set `false` behind pgbouncer in transaction mode |

## Documentation

**Using the plugin**

| | |
|---|---|
| [Generated code](docs/Generated-Code.md) | the files, classes and methods you get, and how they are named |
| [Queries](docs/Queries.md) | annotations, `:copyfrom`, macros, arguments |
| [Types](docs/Types.md) | the Ruby type of every SQL type, time zones, enums |
| [Connections](docs/Connections.md) | pools, shared connections, forked workers, fibers |
| [Transactions](docs/Transactions.md) | commit and rollback, savepoints, isolation, what happens on errors |
| [Options](docs/Options.md) | every option, `overrides` |
| [Troubleshooting](docs/Troubleshooting.md) | known errors and surprises per database, with their fixes |
| [Examples](docs/Examples.md) | schemas, queries and generated output for each database |

**Working on the plugin**

| | |
|---|---|
| [Contributing](docs/Contributing.md) | setup, commands, pull requests |
| [Architecture](docs/Architecture.md) | how the generator works and how it is packed into WebAssembly |
| [Testing](docs/Testing.md) | test layers, CI, what to run before pushing |
| [Coverage](docs/Coverage.md) | every documented behavior and the test that proves it |
| [Releasing](docs/Releasing.md) | the release workflow and versioning |
