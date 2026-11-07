# Design: a sqlc plugin written in Ruby, shipped as WASM

sqlc plugins receive a protobuf `GenerateRequest` on stdin and answer with a `GenerateResponse` on stdout, either as a
process or as a WASI module. This plugin is pure Ruby and is distributed as a WASI module (`plugin.wasm`).

## Source layout
What each file in `lib/sqlc_gen_ruby/` does is in [Architecture.md](Architecture.md). Two constraints shape it:
* `google-protobuf` is a C extension and cannot be loaded inside ruby.wasm, so the plugin brings its own ~150 line
  protobuf codec (`proto.rb`) and the subset of sqlc's `codegen.proto` it reads (`plugin_pb.rb`, field numbers must
  match upstream).
* Driver differences are data, not copy/paste: `Drivers::Base` defines hooks (how to prepare and run a statement, how
  rows are read - `row_data_type` `:hash` for `row['col']` vs `:array` for `row[0]` -, how `:execlastid` /
  `:execresult` / `:copyfrom` / transactions work) and a column mapping table; `Pg`, `Mysql2` and `Sqlite3` fill them in.

## The WASM build (`scripts/wasm/build.sh`)

1. downloads the *prebuilt* `ruby-3.3-wasm32-unknown-wasip1-full` release from ruby/ruby.wasm (this avoids compiling
   CRuby with a wasi-sdk);
2. strips the ~18 MB of DWARF debug info / name section from the interpreter (`strip_wasm.rb`);
3. stages a slim stdlib (the plugin only uses core + `json`) + `lib/` + `exe/`, plus an empty
   `syntax_suggest/core_ext.rb` (the interpreter loads it to format errors and would otherwise print a warning before
   the plugin's error message);
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
PostgreSQL prepared statements are named per query class and remembered per *connection* (a module mixed into each
connection), so several query objects can share a pool. MySQL quotes parameters client-side and sends queries through
`Mysql2::Client#query` rather than server-side prepared statements.

## History
The plugin started as a port of the C# `sqlc-gen-csharp` plugin and reproduced its output byte for byte (verified
against the C# binary; see the git history before the commit that removed the C# code). It has since gained the sqlc features of
that plugin (`:execrows`, `:execlastid` for every driver, `:copyfrom`, `sqlc.slice`, `sqlc.embed`, enums, models,
transactions, nullability, `overrides`) and Ruby conventions (bang finders, logger, pooling), so the output is
now idiomatic Ruby rather than a copy of the C# one.

## Deliberate trade-offs
Things that look like limitations but are design choices (symptoms and fixes: [Troubleshooting](Troubleshooting.md)):
* Overrides only change the RBS types; values are never converted, so the generated code stays a thin layer over the driver.
* SQLite queries do not overlap: a `SQLite3::Database` is one connection, so the generated code takes one lock per
  database (held for a whole transaction) to keep threads and fibers from mixing their transactions.
