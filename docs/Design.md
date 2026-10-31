# Design: a sqlc plugin written in Ruby, shipped as WASM

sqlc plugins receive a protobuf `GenerateRequest` on stdin and answer with a `GenerateResponse` on stdout, either as a
process or as a WASI module. This plugin is pure Ruby and is distributed as a WASI module (`plugin.wasm`).

## Source layout

| File | Role |
|---|---|
| `exe/plugin.rb` | entry point (stdin → `Generator` → stdout) |
| `lib/sqlc_gen_ruby/proto.rb` | ~150 line protobuf wire codec. `google-protobuf` is a C extension and cannot be loaded inside ruby.wasm, so the plugin brings its own |
| `lib/sqlc_gen_ruby/plugin_pb.rb` | the subset of sqlc's `codegen.proto` the generator needs (field numbers must match upstream) |
| `lib/sqlc_gen_ruby/options.rb`, `ruby_version.rb` | the `options:` JSON, `rubyVersion` parsing / validation (3.1 – 3.3; `Struct` below 3.2, `Data` from 3.2) |
| `lib/sqlc_gen_ruby/generator.rb` | module / class / dataclass (`Data.define`, `Struct.new`) layout, `.rb` / `.rbs` / `Gemfile` files |
| `lib/sqlc_gen_ruby/method_gen.rb` | one generated method per query: `:one`, `:many`, `:exec`, `:execlastid` |
| `lib/sqlc_gen_ruby/drivers/*.rb` | `Base` + `Pg`, `Mysql2`, `Sqlite3`: column type mapping, statement preparation / execution, pooling, row access |
| `lib/sqlc_gen_ruby/code.rb` | indent / snake_case helpers (formatting must stay byte-identical with the original implementation) |

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

## Verification strategy

The previous C# implementation defined the expected behaviour. Its output is kept as test data:

* `examples/{pg,mysql2,sqlite3}` — checked-in output of the C# plugin for the example schemas;
* `test/golden/*` — C# output for option variants (Ruby 3.1 `Struct`, 3.2 / no types, `generateGemfile`) over the sqlc
  captured queries plus synthetic ones (5+ params / columns for the multi-line formatting, lower-case names, several
  query files);
* `test/fixtures/*.bin` — real `GenerateRequest`s captured from `sqlc generate` (v1.27.0).

`test/codec_test.rb` cross-checks the hand-written protobuf codec against Google's official implementation (test-only
dependency).

## Known quirks kept for output compatibility
* With Ruby < 3.2 the generated `Struct.new(id, name)` lists bare identifiers, not symbols (`:id, :name`).
  This is what the C# plugin generated, so it is preserved.
* `3.3.x` (a patch version) is rejected: the original version comparison treats a patch as greater than "no patch".
* An unknown `driver` is an error here (the C# enum parse silently fell back to `mysql2`).
