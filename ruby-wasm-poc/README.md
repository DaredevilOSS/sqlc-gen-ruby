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

## What is NOT verified: the `.wasm`

This was developed in a sandbox where downloading and running the release binaries
(ruby.wasm, wasi-vfs, wasmtime, sqlc) was blocked, so **nothing was run inside WASM and
`sqlc generate` was never run against the plugin**. `scripts/build_wasm.sh` is the intended route:
use the *prebuilt* `ruby-3.3-wasm32-unknown-wasip1-full` release (which sidesteps the old
`rbwasm build` `dln.c` / `Dl_info` failure) and `rbwasm pack` the stdlib and `lib/` + `exe/` into it.

### Open problem: argv
sqlc runs a wasm plugin with no arguments, so a bare `ruby` would try to read its *script from stdin*,
which is where the protobuf request arrives. Something has to make the interpreter run
`/app/exe/plugin.rb`. Candidates, in order of preference to try:
1. Check whether `rbwasm pack` / wasi-vfs in the current version can bake in argv.
2. Wrap the module with a tiny shim that overrides `wasi_snapshot_preview1.args_get/args_sizes_get`
   to return `["ruby", "/app/exe/plugin.rb"]` (e.g. via `wasm-merge`/`wasm-tools compose`).
3. Build a custom ruby.wasm whose `main` is fixed.

### Next steps to finish the proof
1. `scripts/build_wasm.sh`, then `wasmtime run dist/plugin.wasm < request.bin` to check the wasm path.
2. Solve argv (above).
3. Point `sqlc.ci.yaml` at `dist/plugin.wasm` and run `sqlc generate`; diff against `examples/`.
4. Port the mysql2 / sqlite3 drivers.
