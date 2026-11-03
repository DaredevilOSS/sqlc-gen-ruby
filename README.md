[![Build](https://github.com/DaredevilOSS/sqlc-gen-ruby/actions/workflows/build.yml/badge.svg?branch=main)](https://github.com/DaredevilOSS/sqlc-gen-ruby/actions/workflows/build.yml)
[![Tests](https://github.com/DaredevilOSS/sqlc-gen-ruby/actions/workflows/tests.yml/badge.svg?branch=main)](https://github.com/DaredevilOSS/sqlc-gen-ruby/actions/workflows/tests.yml)

# sqlc-gen-ruby
A [sqlc](https://sqlc.dev) plugin that generates Ruby code (plus optional RBS type signatures) from SQL.
Supported drivers: `pg`, `mysql2` and `sqlite3`.

The plugin itself is written in Ruby: it is pure Ruby with no native dependencies (it has its own tiny protobuf
codec), and it is shipped as a single self-contained WebAssembly module — the Ruby interpreter
([ruby.wasm](https://github.com/ruby/ruby.wasm)) with the plugin embedded. See [How it works](#documentation).

## Usage

### Options Documentation
| Option          | Possible values                                | Optional | Info                                                                                                      |
|-----------------|------------------------------------------------|----------|-----------------------------------------------------------------------------------------------------------|
| driver          | values: `mysql2`,`pg`, `sqlite3`               | No       | Choosing the driver to use - see [here](docs/Examples.md) for more details info.                          |
| rubyVersion     | default: `3.3`<br/>values: `3.1` - `3.4`       | Yes      | Determines the Ruby version the generated code should support..                                           |
| generateGemfile | default: `false`<br/>values: `false`,`true`    | Yes      | Assists you with the integration of SQLC and Ruby by generating a `Gemfile` with the needed dependencies. |
| generateTypes   | default: `true`<br/>values: `false`,`true`     | Yes      | Determines whether to generate type signatures in addition to the code.                                   |
| overrides       | a list, see [below](#override-option)          | Yes      | Overrides the generated (RBS) type of specific columns / parameters.                                      |
| moduleName      | default: `<Driver>Codegen` (e.g. `PgCodegen`)  | Yes      | The Ruby module the generated code lives in, e.g. `MyApp::Db`.                                            |
| preparedStatements | default: `true`<br/>values: `false`,`true`  | Yes      | `pg` only: `false` sends the SQL with every call (`exec_params`) - needed behind pgbouncer in transaction mode. |

Unknown option names (e.g. a typo such as `moduleNmae`) and `preparedStatements` with a driver other than `pg` are errors.

### Override option
```yaml
overrides:
  - column: "<query-name>:<column-name>"   # one query, e.g. "GetAuthor:bio"
    ruby_type:
      type: "Symbol"
      notNull: true
  - column: "*:<column-name>"              # every query
    ruby_type:
      type: "Pathname"
      notNull: false
```

### Configuration
```yaml
version: "2"
plugins:
- name: ruby
  wasm:
    url: https://github.com/DaredevilOSS/sqlc-gen-ruby/releases/download/${RELEASE_TAG}/sqlc-gen-ruby.wasm
    sha256: ${RELEASE_SHA}
sql:
  # PostgreSQL Example
  - schema: "examples/authors/postgresql/schema.sql"
    queries: "examples/authors/postgresql/query.sql"
    engine: "postgresql"
    codegen:
      - plugin: ruby
        out: examples/pg
        options:
          driver: pg
          rubyVersion: "3.3"
          generateTypes: true
          generateGemfile: false
  # MySQL Example
  - schema: "examples/authors/mysql/schema.sql"
    queries: "examples/authors/mysql/query.sql"
    engine: "mysql"
    codegen:
      - plugin: ruby
        out: examples/mysql2
        options:
          driver: mysql2
          rubyVersion: "3.3"
          generateTypes: true
          generateGemfile: false
  # Sqlite3 Example
  - schema: "examples/authors/sqlite/schema.sql"
    queries: "examples/authors/sqlite/query.sql"
    engine: "sqlite"
    codegen:
      - plugin: ruby
        out: examples/sqlite3
        options:
          driver: sqlite3
          rubyVersion: "3.3"
          generateTypes: true
          generateGemfile: false
```

### [Generated Code Examples](docs/Examples.md)

## Using the generated code
```ruby
require_relative 'db/query_sql'

queries = PgCodegen::QuerySql.connect({ dbname: 'app', host: 'localhost' }, size: 5) # a ConnectionPool

author = queries.create_author(name: 'Seuss', bio: nil)   # :one with RETURNING -> a frozen Data row
queries.get_author(id: author.id)                          # => #<data GetAuthorRow id=1, name="Seuss", bio=nil> or nil
queries.list_authors_paged(limit: 10, offset: 0)           # :many -> Array of rows
queries.get_authors_by_ids(ids: [1, 2, 3])                 # sqlc.slice / array parameter
queries.copy_authors([PgCodegen::CopyAuthorsArgs.new(name: 'a', bio: nil)])   # :copyfrom

queries.transaction(isolation: :serializable) do |tx|      # COMMIT on return (also break / return / throw), ROLLBACK on error
  id = tx.create_author_return_id(name: 'a', bio: nil)
  tx.transaction { |inner| inner.create_book(name: 'b', author_id: id) }   # nested -> SAVEPOINT
end
```
* **Keyword arguments:** every query parameter is a keyword argument (missing / unknown ones raise `ArgumentError`). Parameters named with `sqlc.arg` / `sqlc.narg` that are nullable default to `nil`; a plain nullable column (`INSERT ... VALUES ($1, $2)`) has to be passed explicitly. Names are snake_cased, Ruby keywords and the method's own locals (`client`, `sql`, ...) get a trailing underscore (`class_:`); a `sqlc.arg` used twice is one keyword, repeated `?` of the same column become `id:, id_2:, id_3:`.
* **Bang finders:** every `:one` query also gets a `get_author!` that raises `QuerySql::NotFound` instead of returning `nil` (like `find_by` vs `find`).
* **Logging:** `QuerySql.connect(params, logger: Rails.logger)` / `QuerySql.new(pool, logger: logger)` logs `QuerySql#get_author (0.4ms)` at debug level for every query and transaction (SQL parameters are never logged). Without a logger there is no overhead.
* **Rows** are immutable `Data` objects (a `keyword_init` `Struct` for `rubyVersion` below 3.2; both are built with keywords: `Row.new(id: 1, name: 'a')`), so they work with pattern matching: `case row in { id:, name: }`. Column names that are not valid identifiers are snake_cased (`"Weird Name"` -> `weird_name`), names of the row's own methods get a trailing underscore (`hash` -> `hash_`).
* **Connections:** `QuerySql.connect(params, **pool_options)` builds a [`connection_pool`](https://github.com/mperham/connection_pool); to share a pool you already have (or to inject a fake in tests) use `QuerySql.new(pool)` - anything that responds to `#with` and yields a connection. For SQLite pass a `SQLite3::Database` to `QuerySql.new(db)`.
* **Async / fibers:** the generated code is plain synchronous Ruby and works with the Fiber scheduler (the [`async`](https://github.com/socketry/async) gem): inside `Sync { ... }` pooled queries on `pg` and `mysql2` overlap instead of blocking (see `tests/end2end_pg.rb`). SQLite calls are synchronous C calls and do not overlap.
* **SQL** is kept in frozen heredoc constants (`GET_AUTHOR_SQL`); query comments in the `.sql` file become doc comments on the method; `.rbs` signatures are generated for everything.
* The generated code is RuboCop-clean (`rake rubocop`) and 2-space indented.

## Supported features
✅ supported · 🚫 not offered by the database / sqlc

### Query annotations
| Annotation    | PostgreSQL | MySQL | SQLite | Notes |
|---------------|:---:|:---:|:---:|-------|
| `:one`        | ✅ | ✅ | ✅ | returns the row or `nil` |
| `:many`       | ✅ | ✅ | ✅ | returns an `Array` of rows |
| `:exec`       | ✅ | ✅ | ✅ | |
| `:execrows`   | ✅ | ✅ | ✅ | returns the number of affected rows |
| `:execlastid` | ✅ | ✅ | ✅ | PostgreSQL / SQLite need a `RETURNING <id>` clause (the value of that column is returned); MySQL returns `client.last_id` |
| `:copyfrom`   | ✅ | ✅ | ✅ | takes an `Array` of `<Query>Args` (a generated `Data` class). PostgreSQL: `COPY ... FROM STDIN`. MySQL: `LOAD DATA LOCAL INFILE` from a temporary CSV - needs `local_infile: true` in the `Mysql2::Client` params and `local_infile=1` on the server. SQLite: batched multi-row `INSERT` |

### Macros
| Macro         | PostgreSQL | MySQL | SQLite | Notes |
|---------------|:---:|:---:|:---:|-------|
| `sqlc.arg`    | ✅ | ✅ | ✅ | names the attribute of the `<Query>Args` class (anonymous parameters such as `ANY($1::BIGINT[])` are called `param1`, `param2`, ...) |
| `sqlc.narg`   | ✅ | ✅ | ✅ | nullable parameter, typed `T?` |
| `sqlc.slice`  | 🚫 | ✅ | ✅ | the `IN (...)` list is expanded at runtime (an empty list matches nothing). PostgreSQL: pass an array to `= ANY($1::T[])` instead |
| `sqlc.embed`  | ✅ | ✅ | ✅ | the row gets an attribute holding the table's model (`author`, `author2` for the same table twice) |

### Other
* **Models:** a `models.rb` / `models.rbs` with one `Data` (`Struct` below Ruby 3.2) class per table, and one module with constants per enum (`ExtendedBioType::MEMOIR`, `ExtendedBioType::ALL`). Enum columns are `String`s.
* **Transactions:** `queries.transaction { |tx| tx.create_author(...) }` runs everything in the block on one connection in a transaction (commit when the block returns, also through `break` / `return` / `throw`; rollback when it raises or the thread is killed) and returns the block's value. Nested calls become savepoints; `isolation:` (`pg`, `mysql2`) / `mode:` (`sqlite3`) choose the isolation level / locking mode.
* **Nullability:** nullable columns / parameters are typed `T?` in the `.rbs`.
* **Arrays (PostgreSQL):** `Array[T]` for columns and parameters.
* Types follow the Ruby classes the drivers actually return (e.g. `BigDecimal` for `numeric`/`decimal`, `Date`, `Time`, `IPAddr`; `json`/`jsonb` are parsed, so `untyped`).

Not applicable to the Ruby plugin (they exist in the C# plugin because of its runtime): `withAsyncSuffix` / `withCancellationToken` (Ruby has no async/await: use the Fiber scheduler, see above), `useDapper`, target framework / csproj / namespace options (`moduleName` is the equivalent of the namespace).

# Contributing
## Local plugin development
### Prerequisites
* Ruby 3.3 and `bundle install`
* [sqlc](https://docs.sqlc.dev/en/latest/overview/install.html) (version in [`scripts/tool-versions.env`](scripts/tool-versions.env))
* `curl` + `tar` for building the WASM plugin (it downloads the prebuilt ruby.wasm interpreter)
* PostgreSQL / MySQL servers for the end-to-end tests (or Docker, see below)

### Layout
| Path | What |
|---|---|
| `exe/plugin.rb` | plugin entry point: `GenerateRequest` on stdin → `GenerateResponse` on stdout |
| `lib/sqlc_gen_ruby/` | the generator (`generator.rb`, `method_gen.rb`, `drivers/*.rb`, `options.rb`, ...) |
| `test/` | unit + golden tests (`rake test`); `test/fixtures` are real requests captured from sqlc |
| `tests/` | end-to-end tests of the generated code against real databases |
| `examples/` | the plugin's output for `examples/authors/*` (kept in sync, CI runs `sqlc diff`) |
| `scripts/wasm/` | building the WASM plugin |

### Everyday commands
```
bundle exec rake test                 # unit + golden tests (no database needed)
rake sqlc_generate_process            # regenerate examples/ with exe/plugin.rb (needs `ruby` on PATH)
rake sqlc_generate_wasm               # build dist/plugin.wasm, then regenerate examples/ with it
bundle exec rake rubocop steep        # the generated code must stay RuboCop- and Steep-clean
rake end2end_sqlite3                  # end-to-end, no server needed
rake end2end_pg end2end_mysql2        # end-to-end, needs the servers below
rake run_end2end_tests                # all of it in Docker (docker-compose)
```
The end-to-end tests read `DB_NAME`, `DB_USER`, `DB_PASS`, `POSTGRES_HOST`, `MYSQL_HOST` (and optionally
`POSTGRES_PORT`, `MYSQL_PORT`); load `examples/authors/<db>/schema.sql` into the database first. MySQL needs
`local_infile=1` for `:copyfrom`.

The golden tests feed the plugin real `GenerateRequest`s captured from sqlc and compare with [examples/](examples) and
`test/golden` (`UPDATE_GOLDEN=1 ruby -Itest test/extended_golden_test.rb` rewrites the snapshots - review the diff).
To refresh a fixture see `scripts/capture_request.rb`.

### CI
* **Build** (`build.yml`): builds `plugin.wasm`; lint (Ruby warnings, RuboCop on the generated code); codegen tests -
  `sqlc diff` for the WASM *and* the process plugin, Steep, and generation with different options (Ruby 3.1 / 3.2 / 3.3,
  types, Gemfile) checked with the matching Ruby.
* **Tests** (`tests.yml`): unit tests, the plugin on Ruby 3.1 / 3.2 / 3.4, and the end-to-end tests against PostgreSQL
  and MySQL service containers and SQLite.
* Tool versions live in `scripts/tool-versions.env`; dependabot keeps actions and gems current.

## Release flow
Releases are started by hand and fully automated after that: **Actions → Release → Run workflow** (patch / minor / major,
optional dry run). The workflow runs the whole test gate on the commit, then tags, publishes the GitHub release with the
tested `sqlc-gen-ruby.wasm` and its sha256, and verifies the published file with sqlc. Details: [docs/Releasing.md](docs/Releasing.md).

## Documentation
| Doc | What |
|---|---|
| [docs/Architecture.md](docs/Architecture.md) | how the generator works, where to change what, adding a feature / driver / option |
| [docs/Testing.md](docs/Testing.md) | the test layers, CI workflows, what to run before pushing |
| [docs/Releasing.md](docs/Releasing.md) | the release process and versioning rules |
| [docs/Design.md](docs/Design.md) | the WASM packaging, design decisions, known limitations |
| [docs/Examples.md](docs/Examples.md) | per-driver configs and links to the generated examples |
| [CLAUDE.md](CLAUDE.md) | the same orientation condensed for AI coding assistants |
