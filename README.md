<h1 align="center">sqlc-gen-ruby</h1>

<p align="center">
  A <a href="https://sqlc.dev">sqlc</a> plugin that generates typed Ruby (with RBS signatures) from SQL,
  for PostgreSQL, MySQL and SQLite.
</p>

<p align="center">
  <a href="https://github.com/DaredevilOSS/sqlc-gen-ruby/actions/workflows/build.yml"><img alt="Build" src="https://github.com/DaredevilOSS/sqlc-gen-ruby/actions/workflows/build.yml/badge.svg?branch=main"></a>
  <a href="https://github.com/DaredevilOSS/sqlc-gen-ruby/actions/workflows/tests.yml"><img alt="Tests" src="https://github.com/DaredevilOSS/sqlc-gen-ruby/actions/workflows/tests.yml/badge.svg?branch=main"></a>
  <a href="https://github.com/DaredevilOSS/sqlc-gen-ruby/releases/latest"><img alt="Latest release" src="https://img.shields.io/github/v/release/DaredevilOSS/sqlc-gen-ruby"></a>
  <a href="LICENSE"><img alt="License: MIT" src="https://img.shields.io/github/license/DaredevilOSS/sqlc-gen-ruby"></a>
</p>

> **Status: maintained.** Bugs are fixed and releases are cut from `main` by the maintainer
> ([Doron Eli](https://github.com/doron050)). Issues and pull requests are welcome, see [Contributing](#contributing).

[sqlc](https://sqlc.dev) checks your SQL schema and queries against each other. This plugin turns the result into plain
Ruby: one method per query, one `Data` class per result row, and `.rbs` signatures for all of it. It exists so Ruby
projects can keep SQL as the source of truth without an ORM: the generated code needs only your database gem and
`connection_pool`, and there is no runtime library to depend on.

## Features

* **Engines and drivers:** PostgreSQL with [`pg`](https://rubygems.org/gems/pg), MySQL with
  [`mysql2`](https://rubygems.org/gems/mysql2), SQLite with [`sqlite3`](https://rubygems.org/gems/sqlite3).
* **Ruby 3.1 to 4.0** for the generated code (`rubyVersion` option). Rows are `Data` classes from Ruby 3.2 and `Struct`s
  below. CI runs the end-to-end tests on every Ruby from 3.1 to 4.0.
* **Type signatures:** an `.rbs` file for the queries, models and connection code. Nullable columns and parameters are
  `T?`. CI checks the generated code with Steep and RuboCop.
* **Query annotations:** `:one`, `:many`, `:exec`, `:execrows`, `:execlastid`, `:execresult`, `:batchexec`,
  `:batchone`, `:batchmany` and `:copyfrom`; `:one` queries also get a bang method that raises instead of returning `nil`.
* **Runtime behavior:** connection pooling, transactions with savepoints and isolation levels, optional query logging
  (parameter values are never logged).
* **Platforms:** the plugin is one WebAssembly file, so it runs wherever sqlc runs. CI generates code and runs the
  end-to-end tests on Linux, macOS and Windows.

## Quick start

Install [sqlc](https://docs.sqlc.dev/en/latest/overview/install.html), then add the plugin to `sqlc.yaml`. Take the
URL and sha256 of a version from its [release notes](https://github.com/DaredevilOSS/sqlc-gen-ruby/releases):

```yaml
version: "2"
plugins:
  - name: ruby
    wasm:
      url: https://github.com/DaredevilOSS/sqlc-gen-ruby/releases/download/vX.Y.Z/sqlc-gen-ruby.wasm
      sha256: <sha256 from the release notes>
sql:
  - engine: postgresql        # or mysql / sqlite
    schema: schema.sql
    queries: queries.sql
    codegen:
      - plugin: ruby
        out: app/db
        options:
          driver: pg          # or mysql2 / sqlite3; must match the engine
```

`schema.sql`:

```sql
CREATE TABLE authors (
  id   BIGSERIAL PRIMARY KEY,
  name text NOT NULL,
  bio  text
);
```

`queries.sql`:

```sql
-- name: GetAuthor :one
-- Returns the author with the given id, or nil when there is none.
SELECT * FROM authors WHERE id = $1 LIMIT 1;

-- name: CreateAuthor :one
INSERT INTO authors (name, bio) VALUES ($1, $2) RETURNING *;
```

Run `sqlc generate`. For PostgreSQL this writes `app/db/query_sql.rb`, `query_sql.rbs`, `models.rb`, `models.rbs`,
`connection.rb` and `connection.rbs`. The generated `query_sql.rb` contains (abridged, from [`examples/pg`](examples/pg)):

```ruby
module PgCodegen
  GET_AUTHOR_SQL = <<~'SQL'
    SELECT id, name, bio FROM authors
    WHERE id = $1 LIMIT 1
  SQL

  class GetAuthorRow < ::Data.define(:id, :name, :bio)
  end

  class QuerySql
    # Returns the author with the given id, or nil when there is none.
    def get_author(id:)
      with_client('get_author') do |client|
        query_params = [id]
        result = run_prepared(client, 'PgCodegen::QuerySql#get_author', GET_AUTHOR_SQL, query_params)
        row = result.first
        row && GetAuthorRow.new(row['id'], row['name'], row['bio'])
      end
    end

    # Like #get_author, but raises NotFound when there is no row.
    def get_author!(...)
      get_author(...) || raise(NotFound, 'GetAuthor returned no row')
    end
  end
end
```

and `query_sql.rbs`:

```rbs
class GetAuthorRow
  attr_reader id: ::Integer
  attr_reader name: ::String
  attr_reader bio: ::String?
end

def get_author: (id: ::Integer) -> GetAuthorRow?
def get_author!: (id: ::Integer) -> GetAuthorRow
```

Use it. Add `connection_pool` and `pg` (or `mysql2` / `sqlite3`) to your Gemfile, or set `generateGemfile: true` and the
plugin writes one:

```ruby
require_relative 'app/db/query_sql'

queries = PgCodegen::QuerySql.connect({ dbname: 'app', host: 'localhost' }, size: 5)   # builds a connection pool

author = queries.create_author(name: 'Seuss', bio: nil)
queries.get_author(id: author.id)     # the row, or nil
queries.get_author!(id: 42)           # raises PgCodegen::QuerySql::NotFound

queries.transaction do |tx|           # COMMIT at the end, ROLLBACK if the block raises
  tx.create_author(name: 'a', bio: nil)
end
```

The complete, committed output for every database is in [`examples/`](docs/Examples.md).

## Configuration options

Set them under `options:` of the `codegen` entry (or per plugin under the top-level `options:` of `sqlc.yaml`; a codegen
entry's own options win). Unknown or misspelled options are errors. Details: [Options](docs/Options.md).

| Option | Default | Allowed values | Description |
|---|---|---|---|
| `driver` | required | `pg`, `mysql2`, `sqlite3` | The database gem the code is written for. Must match the sqlc `engine:`. |
| `rubyVersion` | `"3.3"` | `"3.1"` to `"4.0"` (also `"3"` or `"3.1.4"`; quote it) | The oldest Ruby the generated code must run on. `"3"` means 3.1. |
| `generateTypes` | `true` | `true`, `false` | Also generate `.rbs` signatures. |
| `generateGemfile` | `false` | `true`, `false` | Also generate a `Gemfile` with the gems the code needs. |
| `moduleName` | `<Driver>Codegen` (`PgCodegen`, `Mysql2Codegen`, ...) | a constant path such as `MyApp::Db`; not `BasicObject`, `Object` or `Kernel` | The module the generated code lives in. |
| `overrides` | none | list of `{column or db_type, ruby_type: {type, notNull}}` | Change the declared (RBS) type of columns or parameters. Values are never converted. |
| `rename` | none | object, e.g. `{authors: Writer, bio: biography}` | Rename tables (model class) and columns (attribute). |
| `exactTableNames` | `false` | `true`, `false` | Name the model `Authors` instead of the singular `Author`. |
| `preparedStatements` | `true` | `true`, `false` | `pg` only (an error with other drivers). `false` is needed behind pgbouncer in transaction mode. |

## Supported sqlc features and limitations

All three engines support every annotation listed under [Features](#features); see [Queries](docs/Queries.md).

| Macro | PostgreSQL | MySQL | SQLite |
|---|:---:|:---:|:---:|
| `sqlc.arg(name)` | yes | yes | yes |
| `sqlc.narg(name)` | yes | yes | yes |
| `sqlc.slice(ids)` | no (sqlc does not offer it; use `= ANY($1::bigint[])`) | yes | yes |
| `sqlc.embed(table)` | yes | yes | yes |

`:copyfrom` is `COPY` on PostgreSQL, `LOAD DATA LOCAL INFILE` on MySQL and multi-row `INSERT` on SQLite.

Known limitations (the full list, with fixes, is in [Troubleshooting](docs/Troubleshooting.md)):

* Values are what the driver gem returns, so Ruby types differ per engine (for example `boolean` is `true` / `false` on
  PostgreSQL but `Integer` on MySQL and SQLite; `date` and `timestamp` are `String` on SQLite). See [Types](docs/Types.md).
* Batches (`:batchexec`, `:batchone`, `:batchmany`) are not atomic unless wrapped in `transaction`.
* `:copyfrom` is refused with `ON CONFLICT` / `RETURNING` on PostgreSQL and `ON DUPLICATE KEY UPDATE` on MySQL, and needs
  `local_infile` on MySQL.
* Two result columns with the same name (`a.id, b.id`) are a generation error: alias one or use `sqlc.embed`.
* `:execlastid` needs `RETURNING` on PostgreSQL and SQLite; `last_insert_id` of `:execresult` is `nil` on PostgreSQL.
* MySQL queries use client-side quoting, not server-side prepared statements.
* A SQLite database is one connection, so its queries and transactions do not overlap.
* Other databases (SQL Server, ClickHouse, ...) and other Ruby database gems are not supported.

## Why a Ruby plugin packed as WebAssembly

sqlc runs community plugins either as an executable or as a WebAssembly (WASI) module. A WASM module is the practical
way to distribute one: users download a single file and need nothing else installed.

The first versions of this plugin were written in C# (reusing the code of the C# sibling plugin), because an attempt to
package Ruby as a WASM file with `rbwasm` had failed at the time. The plugin is now pure Ruby, so people who use the generated code can read and change the generator in the
language they already know. It is released as the [ruby.wasm](https://github.com/ruby/ruby.wasm) interpreter with the
plugin embedded.

Running inside WASI shapes the code: `lib/` and `exe/` may only use Ruby core and `json`, with no gems, C extensions,
filesystem or network. For example, the plugin has its own small protobuf codec instead of `google-protobuf`. Details:
[Architecture](docs/Architecture.md).

## Development

You need Ruby 3.3, `bundle install`, and [sqlc](https://docs.sqlc.dev/en/latest/overview/install.html) in the version
pinned in [`scripts/tool-versions.env`](scripts/tool-versions.env). Details: [Contributing](docs/Contributing.md).

```bash
bundle exec rake test                # unit + golden tests, no database needed
bundle exec rake rubocop steep       # the generated code in examples/ must stay clean
rake sqlc_generate_process           # regenerate examples/ with exe/plugin.rb
rake sqlc_generate_wasm              # build dist/plugin.wasm, then regenerate examples/ with it
rake end2end_sqlite3                 # end-to-end tests of the generated code, no server needed
rake end2end_pg end2end_mysql2       # need PostgreSQL / MySQL servers, or run everything in Docker:
rake run_end2end_tests
```

Building the WASM (`scripts/wasm/build.sh`) downloads the prebuilt ruby.wasm interpreter and embeds the plugin in it;
it needs `curl` and `tar`.

| Path | What |
|---|---|
| `lib/sqlc_gen_ruby/` | the plugin: generator, per-query code, `drivers/` (everything database-specific), type resolver, options, protobuf codec |
| `exe/plugin.rb` | entry point |
| `examples/authors/<engine>/` | input SQL (`schema.sql`, `query.sql`) |
| `examples/<driver>/` | the generated output, committed; never edit by hand |
| `test/` | unit and golden tests |
| `tests/` | end-to-end tests of the generated code against real databases |
| `scripts/` | WASM build, test helpers, release scripts, docs generation |
| `docs/` | user and contributor documentation |

When a change alters the generated code, regenerate `examples/` and the golden files in the same commit: CI runs
`sqlc diff` and fails on drift. Releases are started by the maintainer with the *Release* workflow, see
[Releasing](docs/Releasing.md).

## Contributing

Issues and pull requests are welcome: use the [issue templates](https://github.com/DaredevilOSS/sqlc-gen-ruby/issues/new/choose)
for bugs and feature requests. A pull request targets `main`, needs the `Build` and `Tests` workflows green, adds a
real-database end-to-end test for new behavior or a bug fix, and gets a label (`bug`, `enhancement`, `documentation`,
or `breaking`). See [Contributing](docs/Contributing.md) and [Testing](docs/Testing.md).

## Documentation

| Using the plugin | Working on the plugin |
|---|---|
| [Generated code](docs/Generated-Code.md) · [Queries](docs/Queries.md) · [Types](docs/Types.md) · [Connections](docs/Connections.md) · [Transactions](docs/Transactions.md) · [Options](docs/Options.md) · [Troubleshooting](docs/Troubleshooting.md) · [Examples](docs/Examples.md) | [Contributing](docs/Contributing.md) · [Architecture](docs/Architecture.md) · [Testing](docs/Testing.md) · [Coverage](docs/Coverage.md) · [Releasing](docs/Releasing.md) |

## License

[MIT](LICENSE).

## See also

* [sqlc community plugins and language support](https://docs.sqlc.dev/en/latest/reference/language-support.html)
* [sqlc-gen-csharp](https://github.com/DaredevilOSS/sqlc-gen-csharp), the sibling plugin for C#
