[![CI](https://github.com/DaredevilOSS/sqlc-gen-ruby/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/DaredevilOSS/sqlc-gen-ruby/actions/workflows/ci.yml)

# sqlc-gen-ruby
A [sqlc](https://sqlc.dev) plugin that generates Ruby code (plus optional RBS type signatures) from SQL.
Supported drivers: `pg`, `mysql2` and `sqlite3`.

The plugin itself is written in Ruby: it is pure Ruby with no native dependencies (it has its own tiny protobuf
codec), and it is shipped as a single self-contained WebAssembly module — the Ruby interpreter
([ruby.wasm](https://github.com/ruby/ruby.wasm)) with the plugin embedded. See [docs/Design.md](docs/Design.md).

## Usage

### Options Documentation
| Option          | Possible values                                | Optional | Info                                                                                                      |
|-----------------|------------------------------------------------|----------|-----------------------------------------------------------------------------------------------------------|
| driver          | values: `mysql2`,`pg`, `sqlite3`               | No       | Choosing the driver to use - see [here](docs/Examples.md) for more details info.                          |
| rubyVersion     | default: `3.3`<br/>values: `3.1`, `3.2`, `3.3` | Yes      | Determines the Ruby version the generated code should support..                                           |
| generateGemfile | default: `false`<br/>values: `false`,`true`    | Yes      | Assists you with the integration of SQLC and Ruby by generating a `Gemfile` with the needed dependencies. |
| generateTypes   | default: `true`<br/>values: `false`,`true`     | Yes      | Determines whether to generate type signatures in addition to the code.                                   |
| overrides       | a list, see [below](#override-option)          | Yes      | Overrides the generated (RBS) type of specific columns / parameters.                                      |

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
| `:copyfrom`   | ✅ | ✅ | ✅ | takes an `Array` of `<Query>Args`. PostgreSQL: `COPY ... FROM STDIN`. MySQL: `LOAD DATA LOCAL INFILE` from a temporary CSV - needs `local_infile: true` in the `Mysql2::Client` params and `local_infile=1` on the server. SQLite: batched multi-row `INSERT` |

### Macros
| Macro         | PostgreSQL | MySQL | SQLite | Notes |
|---------------|:---:|:---:|:---:|-------|
| `sqlc.arg`    | ✅ | ✅ | ✅ | names the attribute of the `<Query>Args` class (anonymous parameters such as `ANY($1::BIGINT[])` are called `param1`, `param2`, ...) |
| `sqlc.narg`   | ✅ | ✅ | ✅ | nullable parameter, typed `T?` |
| `sqlc.slice`  | 🚫 | ✅ | ✅ | the `IN (...)` list is expanded at runtime (an empty list matches nothing). PostgreSQL: pass an array to `= ANY($1::T[])` instead |
| `sqlc.embed`  | ✅ | ✅ | ✅ | the row gets an attribute holding the table's model (`author`, `author2` for the same table twice) |

### Other
* **Models:** a `models.rb` / `models.rbs` with one `Data` (`Struct` below Ruby 3.2) class per table, and one module with constants per enum (`ExtendedBioType::MEMOIR`, `ExtendedBioType::ALL`). Enum columns are `String`s.
* **Transactions:** `queries.transaction { |tx| tx.create_author(...) }` runs everything in the block on one connection in a transaction (commit when the block returns, rollback when it raises) and returns the block's value.
* **Nullability:** nullable columns / parameters are typed `T?` in the `.rbs`.
* **Arrays (PostgreSQL):** `Array[T]` for columns and parameters.
* Types follow the Ruby classes the drivers actually return (e.g. `BigDecimal` for `numeric`/`decimal`, `Date`, `Time`, `IPAddr`; `json`/`jsonb` are parsed, so `untyped`).

Not applicable to the Ruby plugin (they exist in the C# plugin because of its runtime): `withAsyncSuffix`, `withCancellationToken`, `useDapper`, target framework / csproj / namespace options.

# Contributing
## Local plugin development
### Prerequisites
* Ruby 3.3 and `bundle install`
* [sqlc](https://docs.sqlc.dev/en/latest/overview/install.html) (v1.27.0 was used for verification)
* `curl` + `tar` for building the WASM plugin (it downloads the prebuilt ruby.wasm interpreter)
* Docker + docker-compose, for the end-to-end tests only (they need real MySQL / PostgreSQL servers)

### Layout
| Path | What |
|---|---|
| `exe/plugin.rb` | plugin entry point: `GenerateRequest` on stdin → `GenerateResponse` on stdout |
| `lib/sqlc_gen_ruby/` | the generator (`generator.rb`, `method_gen.rb`, `drivers/*.rb`, `options.rb`, ...) |
| `test/` | unit + golden tests (`rake test`); `test/fixtures` are real requests captured from sqlc |
| `tests/` | end-to-end tests of the generated code against real databases |
| `scripts/wasm/` | building the WASM plugin |

### Unit & golden tests
```
bundle exec rake test
```
The golden tests feed the plugin real `GenerateRequest`s captured from sqlc and diff the result against
[examples/](examples) (and against `test/golden`, recorded from the original C# implementation).
To refresh a fixture see `scripts/capture_request.rb`.

### Generating code
SQLC utilizes our process / WASM plugin to generate code
```
rake sqlc_generate_process   # runs exe/plugin.rb directly (needs `ruby` on PATH)
rake sqlc_generate_wasm      # builds dist/plugin.wasm first and runs that
```

### Testing generated code
Testing the SQLC generated code via a predefined flow:
```
rake test_process_plugin
rake test_wasm_plugin
```

### Building the WASM plugin
```
rake wasm_build   # == ./scripts/wasm/build.sh, writes dist/plugin.wasm (~18 MB)
```

## Release flow
The release flow in this repo follows the semver conventions, building tag as `v[major].[minor].[patch]`.

* In order to create a release you need to add `[release]` somewhere in your commit message when merging to master

### Version bumping (built on tags)
**By default, the release script will bump the patch version.**, by adding `[release]` to your commit message the release script will create a new tag with `v[major].[minor].[patch]+1`.
* Bump `minor` version by adding `[minor]` to your commit message resulting in a new tag with `v[major].[minor]+1.0`<br/>
* Bump `major` version by adding `[major]` to your commit message resulting in a new tag with `v[major]+1.0.0`

### Release structure
The new created tag will create a draft release with it, in the release there will be the wasm plugin embedded in the release.<br/>
> Publish the draft
