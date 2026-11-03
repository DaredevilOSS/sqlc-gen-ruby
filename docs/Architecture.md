# Architecture: how the generator works

A sqlc plugin is a program that gets a protobuf `GenerateRequest` on stdin (the parsed schema, the queries, the
plugin's `options:`) and writes a `GenerateResponse` (a list of files) to stdout. This plugin does exactly that in
pure Ruby; [Design.md](Design.md) explains how it is packed into a WASM module.

```
stdin ─► Proto (decode) ─► Generator ─┬─► Options / RubyVersion        what the user asked for
                                      ├─► Catalog                      tables + enums  ─► models.rb
                                      ├─► RowLayout + TypeResolver     result columns  ─► <Query>Row attributes + RBS types
                                      ├─► Drivers::{Pg,Mysql2,Sqlite3} everything that differs per database library
                                      └─► MethodGen                    one Ruby method (+ RBS) per query
                          files ◄─────┘
stdout ◄─ Proto (encode) ◄─ GenerateResponse (query_sql.rb, query_sql.rbs, models.rb, connection.rb, Gemfile, ...)
```

## The pieces

| Piece | Responsibility |
|---|---|
| `exe/plugin.rb` | entry point. Errors go to stderr with exit code 1 (sqlc shows them); `SQLC_GEN_RUBY_DEBUG=1` adds a backtrace |
| `proto.rb`, `plugin_pb.rb` | a ~150 line protobuf wire codec and the subset of sqlc's `codegen.proto` we read. Field numbers must match upstream. `google-protobuf` is a C extension and cannot run inside ruby.wasm |
| `options.rb`, `ruby_version.rb` | parse + validate the `options:` JSON (`driver`, `rubyVersion`, `overrides`, `rename`, ...; unknown keys are errors) |
| `generator.rb` | the orchestrator: one file per query file (`query_sql.rb`), plus `models.rb`, `connection.rb` (per-connection state and helpers the query classes share), `Gemfile`; builds the module / class / `Data` skeleton |
| `method_gen.rb` | the code of one query: signature (keyword arguments), SQL constant, command (`:one`, `:many`, `:exec`, `:execrows`, `:execlastid`, `:execresult`, `:batchexec` / `:batchone` / `:batchmany`, `:copyfrom`), `sqlc.slice`, bang finder, and the RBS signature |
| `row_layout.rb` | turns result columns into row attributes; `sqlc.embed` collapses a table's columns into one model attribute |
| `type_resolver.rb` | RBS type of a column / parameter: driver type table, arrays, nullability (`T?`), `overrides:` (a `db_type` override types array elements too) |
| `catalog.rb` | the schema's tables and enums, and their Ruby names |
| `drivers/base.rb` | the driver interface and what all drivers share: `instrument` logging, `NotFound`, transaction RBS |
| `drivers/{pg,mysql2,sqlite3}.rb` | the per-library parts: type mapping, connecting / pooling, preparing and executing statements, transactions, `:copyfrom` |
| `code.rb` | text helpers: indentation, `snake_case`, `camelize`, Ruby-keyword-safe parameter names, `rubocop:disable` pairs for schema names that break a naming cop |

**Rule of thumb:** `MethodGen` / `Generator` decide *what* is generated and are the same for every database; a driver only
supplies *snippets* (how to prepare a statement, how to read the affected rows, ...). If you find a `case driver` in
`MethodGen`, it belongs in a driver hook instead.

## What the generated code looks like

```ruby
module PgCodegen
  class QuerySql
    GET_AUTHOR_SQL = <<~'SQL'      # raw heredoc: the SQL is never interpolated
      SELECT id, name, bio FROM authors WHERE id = $1 LIMIT 1
    SQL
    GetAuthorRow = Data.define(:id, :name, :bio)   # Struct.new(...) below Ruby 3.2

    def get_author(id:)            # a :one query returns the row or nil ...
      with_client('get_author') do |client|        # one pooled connection + logging
        ...prepare once per connection, exec_prepared...
      end
    end

    def get_author!(id:)           # ... and gets a bang variant
      get_author(id: id) || raise(NotFound, 'GetAuthor returned no row')
    end

    def transaction(isolation: nil) { |tx| ... }   # commit / rollback, nested = SAVEPOINT
  end
end
```
Look at [`examples/pg/query_sql.rb`](../examples/pg/query_sql.rb) for a complete file; it is the plugin's real output.

Design decisions worth knowing (the *why* is in the comments of `drivers/base.rb` and `drivers/pg.rb`):

* **Prepared statements are per connection.** A pooled query object is shared by many connections, and a prepared
  statement exists only on the connection that prepared it, so each connection remembers its own (`ConnectionState`).
* **Pool injection.** `QuerySql.new(pool)` accepts anything that responds to `#with`, so an app can share its pool
  and tests can pass a fake. `connect(...)` is only a convenience that builds a `connection_pool`.
* **Statements are closed.** SQLite/MySQL statements are closed in `ensure` (an open SQLite statement blocks `COMMIT`).
* **Parameters are encoded by the driver.** `Driver#encode_param` (e.g. `bytea`, `json` and arrays on `pg`) is used by
  every command, batches included; add a type's encoding there, not in `MethodGen`.
* **`:copyfrom` is all or nothing** on every driver (a savepoint / transaction around the load), and MySQL's
  `LOAD DATA` warnings (skipped duplicates, coerced values) are raised as errors.
* **Nothing from the plugin leaks into the app.** The generated code only requires the driver gem and `connection_pool`.

## Adding things

**A new query feature** (an annotation or macro):
1. read what sqlc sends in a real request: `scripts/capture_request.rb` saves one to `test/fixtures/` (see [Testing](Testing.md));
2. handle it in `MethodGen` (add a driver hook in `Base` if the code differs per database);
3. add a query using it to `examples/authors/*/{schema,query}.sql` for every driver that can run it;
4. `rake sqlc_generate_process`, review the diff of `examples/`, update the golden files, add unit and end-to-end tests.

**A new driver** (e.g. `trilogy`): subclass `Drivers::Base`, implement the abstract hooks (the abstract ones raise
`NotImplementedError`), register it in `Generator#instantiate_driver` and `Options::DRIVERS`, add `examples/authors/<engine>` + an end-to-end test file `tests/end2end_<driver>.rb`, and a service
container job in `.github/workflows/tests.yml`.

**A new option:** `options.rb` (parse + default), use it where needed, document it in the README option table, and
add a case to `test/options_test.rb` and (if it changes output) to the `codegen-options` matrix in `build.yml`.
