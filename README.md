<h1 align="center">sqlc-gen-ruby</h1>

<p align="center">
  Write SQL. Get typed, idiomatic Ruby.<br>
  A <a href="https://sqlc.dev">sqlc</a> plugin for <b>PostgreSQL</b>, <b>MySQL</b> and <b>SQLite</b>, with RBS signatures.
</p>

<p align="center">
  <a href="https://github.com/DaredevilOSS/sqlc-gen-ruby/actions/workflows/build.yml"><img alt="Build" src="https://github.com/DaredevilOSS/sqlc-gen-ruby/actions/workflows/build.yml/badge.svg?branch=main"></a>
  <a href="https://github.com/DaredevilOSS/sqlc-gen-ruby/actions/workflows/tests.yml"><img alt="Tests" src="https://github.com/DaredevilOSS/sqlc-gen-ruby/actions/workflows/tests.yml/badge.svg?branch=main"></a>
</p>

---

You write the schema and the queries:

```sql
-- name: GetAuthor :one
SELECT * FROM authors WHERE id = $1;

-- name: CreateAuthor :one
INSERT INTO authors (name, bio) VALUES ($1, $2) RETURNING *;
```

`sqlc generate` gives you plain Ruby you call like any other object:

```ruby
queries = PgCodegen::QuerySql.connect({ dbname: 'app', host: 'localhost' }, size: 5)   # a connection pool

author = queries.create_author(name: 'Seuss', bio: nil)   # => #<data CreateAuthorRow id=1, name="Seuss", bio=nil>
queries.get_author(id: author.id)                          # the row, or nil
queries.get_author!(id: 42)                                # raises QuerySql::NotFound

queries.transaction do |tx|                                # COMMIT at the end, ROLLBACK if it raises
  tx.create_author(name: 'a', bio: nil)
end
```

No ORM, no runtime dependency on the plugin, no magic: the SQL stays yours, the Ruby is generated, committed and
reviewable.

## Why you might like it

| | |
|---|---|
| **Three databases** | `pg`, `mysql2` and `sqlite3`, Ruby 3.1 – 4.0. |
| **Typed** | `.rbs` signatures for every model, row and method. The generated code is RuboCop- and Steep-clean. |
| **Idiomatic Ruby** | Keyword arguments, frozen `Data` rows (`Struct` below Ruby 3.2), pattern matching, doc comments from your SQL comments. |
| **Real transactions** | Nested savepoints, isolation levels, safe under `Timeout`, `Thread#kill`, fibers (`async`) and forks (Puma, Sidekiq). |
| **Everything sqlc offers** | `:one` `:many` `:exec` `:execrows` `:execlastid` `:execresult` `:batch*` `:copyfrom`, plus `sqlc.arg` / `narg` / `slice` / `embed`. |
| **Nothing to install but sqlc** | The plugin is pure Ruby shipped as one WebAssembly file ([ruby.wasm](https://github.com/ruby/ruby.wasm)). No Ruby needed to *generate*. |
| **Safe by default** | Parameters are bound (PostgreSQL / SQLite) or escaped by the driver (MySQL), and their values are never logged. |

## Quick start

**1. Point sqlc at the plugin** in `sqlc.yaml`. The URL and sha256 of every version are in its
[release notes](https://github.com/DaredevilOSS/sqlc-gen-ruby/releases).

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

**2. Write your queries** in `db/query.sql` (see above).

**3. Run `sqlc generate`** and `require_relative 'app/db/query_sql'`.

Add the gems the generated code uses (`pg`, `mysql2` or `sqlite3`, and `connection_pool`), or set
`generateGemfile: true` to get a ready `Gemfile`.

> Want to see the output first? [docs/Examples.md](docs/Examples.md) shows the real generated code for every driver,
> built from [these schemas and queries](examples/authors).

## What you get

For each query file `foo.sql`, in `out:`:

| File | Contents |
|---|---|
| `foo_sql.rb` | `FooSql`: one method per query, plus `transaction` |
| `models.rb` | one class per table, one module of constants per enum |
| `connection.rb` | shared helpers |
| `*.rbs` | type signatures for all of the above |

How it feels to use (details in [Generated code](docs/Generated-Code.md)):

* **Arguments** are keywords (`get_author(id:)`); missing or unknown ones raise `ArgumentError`.
* **Rows** are frozen `Data` objects (or keyword `Struct`s below Ruby 3.2) and work with pattern matching.
* **Bang finders**: every `:one` query also has `get_author!`.
* **Pooling**: `connect` builds a [`connection_pool`](https://github.com/mperham/connection_pool); or pass your own to
  `QuerySql.new(pool)`. SQLite takes a `SQLite3::Database`.
* **Logging**: `connect(params, logger: Rails.logger)` logs `QuerySql#get_author (0.4ms)`, never the values.

## Query annotations

| Annotation | Returns |
|---|---|
| `:one` | the row or `nil` (+ a `!` finder) |
| `:many` | an `Array` of rows |
| `:exec` | `nil` |
| `:execrows` | the number of affected rows |
| `:execlastid` | the new id |
| `:execresult` | `ExecResult` (`rows_affected`, `last_insert_id`) |
| `:batchexec` `:batchone` `:batchmany` | run the query once per element of an `Array`, on one connection |
| `:copyfrom` | bulk insert (`COPY` / `LOAD DATA` / multi-row `INSERT`) |

Per-database notes and conflict-clause rules: [Queries](docs/Queries.md).

## sqlc macros

| Macro | PostgreSQL | MySQL | SQLite |
|---|:---:|:---:|:---:|
| `sqlc.arg(name)` | ✅ | ✅ | ✅ |
| `sqlc.narg(name)` (nullable, defaults to `nil`) | ✅ | ✅ | ✅ |
| `sqlc.slice(ids)` (`IN (...)` with an `Array`) | use `= ANY($1::bigint[])` | ✅ | ✅ |
| `sqlc.embed(table)` (the row holds the table's model) | ✅ | ✅ | ✅ |

## Transactions

```ruby
queries.transaction(isolation: :serializable) do |tx|
  id = tx.create_author_return_id(name: 'a', bio: nil)
  tx.transaction { tx.create_book(name: 'b', author_id: id) }   # nested: a SAVEPOINT
  :done                                                          # the block's value is returned
end
```

Commit on exit, rollback on exception, savepoints for nesting. `tx` stays in the transaction from any fiber or thread
and raises `TransactionEnded` once it is over. Dead connections, timeouts, killed threads, forks, deadlocks and shared
connections (ActiveRecord, Sequel) are all handled and documented in [Transactions and connections](docs/Transactions.md).

## Options

| Option | Default | What it does |
|---|---|---|
| `driver` | required | `pg`, `mysql2` or `sqlite3`; must match the sqlc `engine:` |
| `rubyVersion` | `3.3` | oldest Ruby the code must run on (`3.1` – `4.0`) |
| `generateTypes` | `true` | also generate `.rbs` signatures |
| `generateGemfile` | `false` | also generate a `Gemfile` with the gems the code needs |
| `moduleName` | `<Driver>Codegen` | the module the code lives in, e.g. `MyApp::Db` |
| `overrides` | none | change the Ruby type of columns / parameters |
| `rename` | none | rename tables and columns, e.g. `{authors: Writer, bio: biography}` |
| `exactTableNames` | `false` | keep `authors` as `Authors` instead of singularizing to `Author` |
| `preparedStatements` | `true` | `pg` only; `false` for pgbouncer in transaction mode |

Misspelled options are errors with a "did you mean" hint. Full reference, overrides and `sqlc.yaml`-level sharing:
[Options](docs/Options.md).

## Types

| SQL | Ruby |
|---|---|
| integers / floats | `Integer` / `Float` |
| `numeric`, `decimal` | `BigDecimal` |
| text, enums | `String` (enums also get constants: `ExtendedBioType::MEMOIR`) |
| dates / times | `Date` / `Time` |
| `inet`, `cidr` | `IPAddr` |
| `json`, `jsonb` (PostgreSQL) | parsed (`untyped`) |
| PostgreSQL arrays | `Array[T]` |
| nullable | `T?` |

Types follow what each driver returns. Time-zone behavior, the exotic PostgreSQL types, MySQL `JSON`, SQLite affinity
and naming rules (keywords, acronyms, clashing columns) are in [Types and names](docs/Types.md).

## Good to know

The plugin is deliberately direct, so a few things work differently from what you might expect. The ones people hit
first:

| Database | Heads-up | Do this |
|---|---|---|
| all | Two result columns with the same name (`a.id, b.id`) are a generation error | alias one, or use `sqlc.embed` |
| all | `:batch*` calls are not atomic | wrap them in `transaction` |
| all | `timestamp` / `DATETIME` store local wall-clock time | use `timestamptz` / `TIMESTAMP`, or run with `TZ=UTC` |
| PostgreSQL | no `sqlc.slice` | `= ANY($1::bigint[])` |
| PostgreSQL | prepared statements break behind pgbouncer (transaction mode) | `preparedStatements: false` |
| MySQL | no server-side prepared statements (client-side quoting); `:copyfrom` needs `local_infile` | enable it on client and server |
| MySQL | `sqlc.embed` lowercases table names | alias the table: `` sqlc.embed(m) FROM `MixedItems` AS m `` |
| SQLite | sqlc breaks queries in files with non-ASCII characters | keep query files ASCII, pass values as parameters |
| SQLite | `ON CONFLICT ... DO UPDATE` with `sqlc.arg` is a generation error | use `excluded.<column>` |
| SQLite | at most 32,766 parameters per statement | `:copyfrom` into a table and join |

Everything else, with the reasons: [Limitations](docs/Limitations.md).

## Documentation

| | |
|---|---|
| [Generated code](docs/Generated-Code.md) | files, rows, finders, logging, style |
| [Queries](docs/Queries.md) | annotations, `:copyfrom`, macros, arguments |
| [Transactions and connections](docs/Transactions.md) | transactions, pools, forks, Async, shared connections |
| [Types and names](docs/Types.md) | type mapping, time zones, enums, naming rules |
| [Options](docs/Options.md) | every option and `overrides` |
| [Limitations](docs/Limitations.md) | the complete list, per database |
| [Examples](docs/Examples.md) | per-driver configs and generated output |

## Contributing

Contributions are welcome. You need Ruby 3.3 (`bundle install`), [sqlc](https://docs.sqlc.dev/en/latest/overview/install.html)
(version in [`scripts/tool-versions.env`](scripts/tool-versions.env)), `curl` + `tar` to build the WASM, and
PostgreSQL / MySQL servers (or Docker) for the end-to-end tests.

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

Releases are started by a maintainer (**Actions → Release → Run workflow**) and are automated from there: the full test
gate, the tag, the GitHub release with the tested `sqlc-gen-ruby.wasm` and its sha256, and a check of the published file.

| Doc | What |
|---|---|
| [docs/Architecture.md](docs/Architecture.md) | how the generator works, where to change what, adding a feature / driver / option |
| [docs/Testing.md](docs/Testing.md) | the test layers, CI workflows, what to run before pushing |
| [docs/Releasing.md](docs/Releasing.md) | the release process and versioning rules |
| [docs/Design.md](docs/Design.md) | the WASM packaging and design decisions |
| [docs/Coverage.md](docs/Coverage.md) | every documented behavior mapped to its end-to-end test |
| [CLAUDE.md](CLAUDE.md) | the same orientation condensed for AI coding assistants |
