# Architecture

How the generator works, why it is built this way, and where to change what.

## What a sqlc plugin is

sqlc parses the schema and the queries, then hands the plugin a protobuf `GenerateRequest` on stdin (tables, enums,
queries with their typed parameters and columns, and the plugin's `options:`). The plugin answers on stdout with a
`GenerateResponse`: a list of files. sqlc can run a plugin as a process or as a WASI module.

This plugin is pure Ruby. It runs as a process during development (`exe/plugin.rb`) and is released as one WASI module:
the [ruby.wasm](https://github.com/ruby/ruby.wasm) interpreter with the plugin inside
([Packaging](#packaging-as-webassembly)).

## The pipeline

```
stdin ─► Proto (decode) ─► Generator ─┬─► Options / RubyVersion        what the user asked for
                                      ├─► Catalog                      tables + enums  ─► models.rb
                                      ├─► RowLayout + TypeResolver     result columns  ─► <Query>Row attributes + RBS types
                                      ├─► Drivers::{Pg,Mysql2,Sqlite3} everything that differs per database library
                                      └─► MethodGen                    one Ruby method (+ RBS) per query
                          files ◄─────┘
stdout ◄─ Proto (encode) ◄─ GenerateResponse (query_sql.rb, query_sql.rbs, models.rb, connection.rb, Gemfile, ...)
```

Everything is in `lib/sqlc_gen_ruby/`:

| File | Responsibility |
|---|---|
| `exe/plugin.rb` | entry point. Errors go to stderr with exit code 1 (sqlc shows them); `SQLC_GEN_RUBY_DEBUG=1` adds a backtrace |
| `proto.rb`, `plugin_pb.rb` | a small protobuf wire codec and the subset of sqlc's `codegen.proto` the plugin reads. Field numbers must match upstream |
| `options.rb`, `ruby_version.rb` | parse and validate the `options:` JSON; unknown keys are errors |
| `generator.rb` | the orchestrator: one file per query file, plus `models.rb`, `connection.rb` and `Gemfile`; builds the module / class / row skeleton |
| `method_gen.rb` | the code of one query: signature, SQL constant, the annotation's behavior, `sqlc.slice`, the bang method, and the RBS signature |
| `row_layout.rb` | turns result columns into row attributes; `sqlc.embed` collapses a table's columns into one model attribute |
| `type_resolver.rb` | the RBS type of a column or parameter: driver type table, arrays, nullability, `overrides` |
| `catalog.rb` | the schema's tables and enums, and their Ruby names |
| `drivers/base.rb` | the driver interface and what all drivers share: logging, `NotFound`, transaction RBS |
| `drivers/{pg,mysql2,sqlite3}.rb` | the per-library parts: type mapping, connecting and pooling, executing statements, transactions, `:copyfrom` |
| `code.rb` | text helpers: indentation, `snake_case`, `camelize`, keyword-safe names, `rubocop:disable` pairs |

**The one rule:** `MethodGen` and `Generator` decide *what* is generated and are the same for every database. A driver
only supplies *snippets* (how to prepare a statement, how to read the affected rows, ...) through the hooks of
`Drivers::Base`. A `case driver` in `MethodGen` belongs in a driver hook instead.

## The generated code

Abridged from [`examples/pg/query_sql.rb`](../examples/pg/query_sql.rb), the plugin's real output:

```ruby
module PgCodegen
  GET_AUTHOR_SQL = <<~'SQL'        # raw heredoc: the SQL is never interpolated
    SELECT id, name, bio FROM authors
    WHERE id = $1 LIMIT 1
  SQL

  class GetAuthorRow < ::Data.define(:id, :name, :bio)   # a keyword Struct below Ruby 3.2
  end

  class QuerySql
    def get_author(id:)            # a :one query returns the row or nil ...
      with_client('get_author') do |client|        # one pooled connection + logging
        query_params = [id]
        result = run_prepared(client, 'PgCodegen::QuerySql#get_author', GET_AUTHOR_SQL, query_params)
        row = result.first
        row && GetAuthorRow.new(row['id'], row['name'], row['bio'])
      end
    end

    def get_author!(...)           # ... and gets a bang variant
      get_author(...) || raise(NotFound, 'GetAuthor returned no row')
    end
  end
end
```

## Design decisions

The *why* behind most of these is in the comments of `drivers/base.rb` and `drivers/pg.rb`.

* **Idiomatic Ruby, not a port.** The plugin started as a port of
  [sqlc-gen-csharp](https://github.com/DaredevilOSS/sqlc-gen-csharp). Its output now follows Ruby conventions instead:
  keyword arguments rather than parameter objects, `Data` rows, implicit returns, bang methods, 2-space indentation.
* **Nothing from the plugin leaks into the application.** The generated code only requires the driver gem and
  `connection_pool`.
* **A thin layer over the driver.** Values are never converted: `overrides` only change the RBS types.
* **Pool injection.** `QuerySql.new(pool)` accepts anything that responds to `#with`, so an application can share its
  pool and tests can pass a fake. `connect(...)` is only a convenience that builds a `connection_pool`.
* **PostgreSQL prepared statements are per connection.** A query object is shared by many pooled connections, and a
  prepared statement exists only on the connection that prepared it, so each connection remembers its own
  (`ConnectionState`, a module mixed into the connection). Statements are named per module and query class, so several
  query objects can share a pool.
* **MySQL quotes parameters client-side** and uses `Mysql2::Client#query`, not server-side prepared statements, so
  queries cooperate with the Fiber scheduler.
* **SQLite queries do not overlap.** A `SQLite3::Database` is one connection, so the generated code takes one lock per
  database (held for a whole transaction) to keep threads and fibers from mixing their transactions. Statements are
  closed in `ensure`, because an open statement blocks `COMMIT`.
* **Parameters are encoded by the driver.** `Driver#encode_param` (`bytea`, `json` and arrays on `pg`) is used by every
  annotation, batches included. Add a type's encoding there, not in `MethodGen`.
* **`:copyfrom` is all or nothing** on every driver (a savepoint or transaction around the load), and MySQL's
  `LOAD DATA` warnings (skipped duplicates, coerced values) are raised as errors.

## Packaging as WebAssembly

sqlc gives a WASI plugin no filesystem, no network and no way to install gems. That shapes the plugin:

* `lib/` and `exe/` use only Ruby core and `json`.
* `google-protobuf` is a C extension and cannot be loaded inside ruby.wasm, so the plugin has its own codec
  (`proto.rb`).

`scripts/wasm/build.sh` builds `dist/plugin.wasm`:

1. download the *prebuilt* `ruby-3.3-wasm32-unknown-wasip1-full` release of ruby.wasm (no need to compile CRuby);
2. strip the ~18 MB of DWARF debug info and names from the interpreter (`strip_wasm.rb`);
3. stage a slim stdlib, `lib/` and `exe/`, plus an empty `syntax_suggest/core_ext.rb` (the interpreter loads it to
   format errors and would otherwise print a warning before the plugin's own error message);
4. embed that filesystem into the interpreter with `rbwasm pack` (wasi-vfs).

**The argv trick:** sqlc runs the module as `plugin.wasm /plugin.CodegenService/Generate`, and the interpreter takes
that path as its script. The build embeds a file at exactly that path containing `load '/app/exe/plugin.rb'`.

Tool versions (sqlc, ruby.wasm) are pinned in [`scripts/tool-versions.env`](../scripts/tool-versions.env).

## Adding things

**A query feature** (an annotation or macro):

1. look at what sqlc sends: `scripts/capture_request.rb` saves a real request to `test/fixtures/`;
2. handle it in `MethodGen`, with a hook in `Drivers::Base` if the code differs per database;
3. add a query that uses it to `examples/authors/*/{schema,query}.sql` for every database that can run it;
4. run `rake sqlc_generate_process`, read the diff of `examples/`, update the golden files;
5. add end-to-end tests and list them in [Coverage](Coverage.md) ([Testing](Testing.md)); document the feature.

**An option:**

1. parse and default it in `options.rb`, and use it where needed;
2. document it in [Options](Options.md) and the README option table;
3. add a case to `test/options_test.rb` and, if it changes the output, to the `codegen-options` matrix in `build.yml`.

**A driver** (for example `trilogy`):

1. subclass `Drivers::Base` and implement its hooks (the required ones raise `NotImplementedError`);
2. register it in `Generator#instantiate_driver` and `Options::DRIVERS`;
3. add `examples/authors/<engine>/`, an end-to-end suite `tests/end2end_<driver>.rb` and its job in
   `.github/workflows/tests.yml`.
