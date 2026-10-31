# sqlc-gen-ruby in Ruby (POC)

Goal: write the sqlc plugin in Ruby instead of C#, and ship it as a `.wasm`.

## What works (verified)

The plugin logic is now **pure Ruby with zero native dependencies**:

| File | Replaces |
|---|---|
| `lib/sqlc_gen_ruby/proto.rb` | `google-protobuf` (a C extension, which cannot run inside ruby.wasm). A ~150 line wire-format codec. |
| `lib/sqlc_gen_ruby/plugin_pb.rb` | The generated `GenerateRequest/Query/Column/...` classes (subset of `codegen.proto`). |
| `lib/sqlc_gen_ruby/generator.rb`, `drivers/pg.rb`, `options.rb`, `code.rb` | `CodeGenerator.cs`, `PgDriver.cs`, `MethodGen.cs`, `RubySyntax/*`, `PluginOptions/*`. |
| `exe/plugin.rb` | `PluginRunner.cs`: stdin = `GenerateRequest`, stdout = `GenerateResponse`. |

`test/golden_test.rb` runs `exe/plugin.rb` as a subprocess over stdin/stdout (the way sqlc does)
with a request built by the official `google-protobuf` gem, and asserts the generated
`query_sql.rb` / `query_sql.rbs` equal what the C# plugin produced (`examples/pg`), ignoring CRs
and the trailing newline.

```bash
cd ruby-wasm-poc && bundle install && bundle exec ruby test/golden_test.rb
```

Scope of the port: only the `pg` driver and the `:one` / `:many` / `:exec` commands. `mysql2`,
`sqlite3` and `:execlastid` still need porting (the structure in `drivers/pg.rb` is the template).

## The WASM plugin (verified end to end)

`scripts/build_wasm.sh` produces `dist/plugin.wasm` (~37 MB, one self-contained file):

1. downloads the *prebuilt* `ruby-3.3-wasm32-unknown-wasip1-full` release (this sidesteps the old
   `rbwasm build` `dln.c` / `Dl_info` failure entirely);
2. stages a slim filesystem (core stdlib minus bundler/rdoc/irb/etc. + `lib/` + `exe/`);
3. embeds it into the interpreter with `rbwasm pack` (wasi-vfs), since sqlc gives plugins no filesystem.

**The argv problem is solved by a trick:** sqlc runs the module as `plugin.wasm /plugin.CodegenService/Generate`,
so the interpreter treats that path as its script. The build embeds a file at exactly that path containing
`load '/app/exe/plugin.rb'`.

Verified with sqlc v1.27.0 (`wasm: url: file://...dist/plugin.wasm`) on `examples/authors/postgresql`:
`sqlc generate` takes ~2s and the generated `query_sql.rb` / `.rbs` are identical to the C# plugin's
(`examples/pg`), ignoring CRs. Also checked under wasmtime v27: WASM output is byte-identical to native Ruby.

```bash
gem install ruby_wasm && ruby-wasm-poc/scripts/build_wasm.sh   # set RBWASM="ruby /path/to/rbwasm" if rbwasm isn't on PATH
```

## Remaining work
- Port the `mysql2` and `sqlite3` drivers and `:execlastid` (use `drivers/pg.rb` as the template).
- Port the remaining C# options/edge cases (e.g. `generateGemfile` path is written but untested).
- Shrink the wasm (37 MB, mostly the interpreter) and wire it into CI (`sqlc.ci.yaml`).
- Decide on removing the C# projects once the Ruby port has parity.
