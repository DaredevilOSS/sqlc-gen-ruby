# Design: a sqlc plugin written in Ruby, shipped as WASM

sqlc plugins receive a protobuf `GenerateRequest` on stdin and answer with a `GenerateResponse` on stdout, either as a
process or as a WASI module. This plugin is pure Ruby and is distributed as a WASI module (`plugin.wasm`).

## Source layout

| File | Role |
|---|---|
| `exe/plugin.rb` | entry point (stdin → `Generator` → stdout) |
| `lib/sqlc_gen_ruby/proto.rb` | ~150 line protobuf wire codec. `google-protobuf` is a C extension and cannot be loaded inside ruby.wasm, so the plugin brings its own |
| `lib/sqlc_gen_ruby/plugin_pb.rb` | the subset of sqlc's `codegen.proto` the generator needs (field numbers must match upstream) |
| `lib/sqlc_gen_ruby/options.rb`, `ruby_version.rb` | the `options:` JSON, `rubyVersion` parsing / validation (3.1 – 3.4; `Struct` below 3.2, `Data` from 3.2) |
| `lib/sqlc_gen_ruby/generator.rb` | module / class / dataclass (`Data.define`, `Struct.new`) layout, `.rb` / `.rbs` / `Gemfile` files, `models.rb` (tables + enums) |
| `lib/sqlc_gen_ruby/method_gen.rb` | one generated method per query: `:one`, `:many`, `:exec`, `:execrows`, `:execlastid`, `:copyfrom`, `sqlc.slice` |
| `lib/sqlc_gen_ruby/row_layout.rb` | how result columns become `<Query>Row` attributes (`sqlc.embed` expands a table into one model attribute) |
| `lib/sqlc_gen_ruby/type_resolver.rb`, `catalog.rb` | RBS type of a column (DB type mapping + array + nullability + `overrides:`), tables / enums of the catalog |
| `lib/sqlc_gen_ruby/drivers/*.rb` | `Base` + `Pg`, `Mysql2`, `Sqlite3`: column type mapping, statement preparation / execution, pooling, row access |
| `lib/sqlc_gen_ruby/code.rb` | indent / snake_case helpers |

Driver differences are data, not copy/paste: `Base` has `pooling_enabled?` (ConnectionPool vs a single injected
connection), `row_data_type` (`row['col']` vs `row[0]`), `supports_exec_last_id?` (mysql2 only) and a column mapping
table (exact or prefix based matching).

## The WASM build (`scripts/wasm/build.sh`)

1. downloads the *prebuilt* `ruby-3.3-wasm32-unknown-wasip1-full` release from ruby/ruby.wasm (this avoids compiling
   CRuby with a wasi-sdk);
2. strips the ~18 MB of DWARF debug info / name section from the interpreter (`strip_wasm.rb`);
3. stages a slim stdlib (the plugin only uses core + `json`) + `lib/` + `exe/`;
4. embeds that filesystem into the interpreter with `rbwasm pack` (wasi-vfs), because sqlc gives plugins no filesystem.

**The argv trick:** sqlc runs the module as `plugin.wasm /plugin.CodegenService/Generate`, so the interpreter treats that
path as its script. The build embeds a file at exactly that path containing `load '/app/exe/plugin.rb'`.

## Verification
How the plugin is tested (golden files from real sqlc requests, `sqlc diff` over `examples/`, end-to-end tests
against real databases) is described in [Testing.md](Testing.md); how it works inside in [Architecture.md](Architecture.md).

## What the generated code looks like (and why)
Generated code follows what Ruby code usually looks like rather than mirroring the C# plugin: keyword arguments instead of
parameter objects, `Data` rows, implicit returns, `result.map { ... }`, 2-space indentation, a frozen-string-literal
header, SQL in raw heredocs, `connection_pool` for pooling with an injectable pool, nested transactions via savepoints.
Prepared statements are named per query class and remembered per *connection* (a module mixed into each connection),
so several query objects can share a pool.

## History
The plugin started as a port of the C# `sqlc-gen-csharp` plugin and reproduced its output byte for byte (verified
against the C# binary; see the git history before the commit that removed the C# code). It has since gained the sqlc features of
that plugin (`:execrows`, `:execlastid` for every driver, `:copyfrom`, `sqlc.slice`, `sqlc.embed`, enums, models,
transactions, nullability, `overrides`) and Ruby conventions (bang finders, logger, pooling), so the output is
now idiomatic Ruby rather than a copy of the C# one.

## Known limitations
* The SQLite `NUMERIC` affinity can return Integers where `Float` is declared.
* `:copyfrom` for MySQL writes binary (`BLOB`) values through a text CSV; only text-safe values round-trip.
* The generated query classes are not thread-safe for SQLite (a single connection is injected).
* `3.3.x` (a patch version) is rejected as `rubyVersion`; use `3.3`.
