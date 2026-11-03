# CLAUDE.md

sqlc-gen-ruby: a [sqlc](https://sqlc.dev) plugin, written in pure Ruby, that generates Ruby data-access code (+ RBS)
for `pg`, `mysql2` and `sqlite3`. It ships as one WASM module (the ruby.wasm interpreter with the plugin embedded).
Docs: [Architecture](docs/Architecture.md) · [Testing](docs/Testing.md) · [Releasing](docs/Releasing.md) · [Design](docs/Design.md).

## Commands
```
bundle exec rake test                      # unit + golden tests, no database (run this constantly)
bundle exec rake rubocop steep             # the GENERATED code in examples/ must stay clean
rake sqlc_generate_process                 # regenerate examples/ with exe/plugin.rb (needs sqlc >= scripts/tool-versions.env)
rake sqlc_generate_wasm                    # same through the real WASM (slow: builds dist/plugin.wasm)
rake end2end_sqlite3                       # E2E of the generated code, no server; end2end_pg / end2end_mysql2 need servers
UPDATE_GOLDEN=1 bundle exec ruby -Itest test/extended_golden_test.rb   # rewrite test/golden after an intended change
```

## Where things are
* `lib/sqlc_gen_ruby/` – the plugin: `generator.rb` (files), `method_gen.rb` (one method per query), `drivers/*.rb`
  (everything database-specific), `type_resolver.rb`, `row_layout.rb`, `options.rb`, `proto.rb` (own protobuf codec).
* `examples/authors/<engine>/{schema,query}.sql` → input; `examples/<driver>/` → **generated output, committed, never edit by hand**.
* `test/` unit + golden (+ `fixtures/*.bin`, real sqlc requests); `tests/` end-to-end against databases.
* `scripts/` build (`wasm/`), test helpers (`tests/`), release (`releasing/`), docs generation (`docs/`).

## Rules that are easy to break
* **Changing generator output means regenerating `examples/`** (`rake sqlc_generate_process`) and the golden files in
  the same commit; CI runs `sqlc diff` and fails on drift. Read the diff of generated files before committing.
* **Driver differences live in `drivers/*.rb` hooks, not in `if driver ==` inside `method_gen.rb`.**
* **The plugin runs inside ruby.wasm**: only Ruby core + `json`; no gems, no C extensions, no filesystem, no network.
  Anything `require`d by `lib/` or `exe/` must exist in the WASM (`scripts/wasm/build.sh` stages the stdlib). Gems used
  only by tests/tooling go in the `Gemfile` groups, never in `lib/`.
* **Generated code must stay valid for Ruby 3.1–4.0** (`Struct` below 3.2, `Data` from 3.2) and RuboCop/Steep-clean.
* Generated code is plain, idiomatic Ruby (keyword args, `Data` rows, implicit returns, 2-space indent); do not mirror
  the C# sibling plugin's style. Parameter *values* are never logged.
* PostgreSQL prepared statements are per connection (`ConnectionState`) because the query object is shared by pooled
  connections. MySQL uses client-side quoting and `Mysql2::Client#query` instead of server-side prepared statements.
* Every README claim or supported feature needs a real-database E2E test for each applicable engine, listed in
  `docs/Coverage.md`. A bug fix starts with an E2E test that fails before the fix; use unit tests only where E2E cannot
  reach the behavior (for example option validation or generation errors).
* E2E coverage runs on every supported Ruby and includes full-suite option variants. Update `docs/Coverage.md` and
  `docs/Testing.md` with new supported behavior and its test names.
* sqlc runs process plugins with an empty env (`env: [PATH]` is needed in `sqlc.local.yaml`) and resolves `out:`
  relative to the config file.

## Git, CI and releases
* Develop on a feature branch, small commits; PRs target `main`. Label PRs (`bug`, `enhancement`, `documentation`; `breaking` for incompatible changes, see `.github/release.yml`).
* CI: `build.yml` (WASM, lint, `sqlc diff`, Steep, option matrix) and `tests.yml` (unit, compatibility Ruby
  3.1/3.2/3.4/4.0, full E2E Ruby 3.1–4.0, Ruby 4.0 module-name variants and PostgreSQL without prepared statements,
  plus generator-options E2E on Ruby 3.1/4.0 against PostgreSQL 16, MySQL 8.3 and SQLite). Both must be green.
* **Never create tags or releases by hand and never add release markers to commit messages.** Releases are started by a
  maintainer with the *Release* workflow (`docs/Releasing.md`); do not trigger it unless explicitly asked.
* Tool versions (sqlc, ruby.wasm) are pinned in `scripts/tool-versions.env`; bump them there only.
