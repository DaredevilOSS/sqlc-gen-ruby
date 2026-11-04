# Testing and CI

Every README claim and supported feature needs a real-database E2E test for each applicable engine, listed in
[`Coverage.md`](Coverage.md). A bug fix starts with a real-database E2E regression that fails before the fix. Use unit
tests only where E2E cannot reach the behavior, such as option validation or generation errors. CI runs the full E2E
suites on every supported Ruby version plus full-suite option variants; generator-options E2E runs on Ruby 3.1 and 4.0.

There are four layers. Each one answers a different question, and each runs in CI.

| Layer | Command | Needs | Question it answers |
|---|---|---|---|
| Unit + golden | `bundle exec rake test` | nothing | does the plugin produce the expected files? |
| Generated-code checks | `bundle exec rake rubocop steep` | nothing | is the generated code clean Ruby with correct types? |
| `sqlc diff` | `rake sqlc_generate_process` / `sqlc_generate_wasm` | sqlc | do the committed `examples/` match the plugin, through the real sqlc and the real WASM? |
| End-to-end | `rake end2end_sqlite3` / `end2end_pg` / `end2end_mysql2` | databases | does the *generated code* behave correctly against a real database? |

## Unit and golden tests (`test/`)
* `golden_test.rb` runs the plugin on **real requests captured from sqlc** (`test/fixtures/*.bin`) and compares with
  the checked-in `examples/`. `extended_golden_test.rb` does the same for option variants (Ruby 3.1/3.2, no types,
  `generateGemfile`, ...) and synthetic requests (`synthetic_requests.rb`) against `test/golden/`.
  After an intended output change: `UPDATE_GOLDEN=1 bundle exec ruby -Itest test/extended_golden_test.rb`, then **read the diff**.
* `features_test.rb` / `options_test.rb`: one focused test per feature or option.
* `codec_test.rb` cross-checks the hand-written protobuf codec against Google's `google-protobuf` (test-only gem).
* Refreshing a fixture after a new sqlc version or schema change: `scripts/capture_request.rb` (see its header).

## `examples/` is both documentation and a test
`examples/authors/<engine>/{schema,query}.sql` are the inputs; `examples/<driver>/` is the plugin's output, committed.
CI runs `sqlc diff` against it, so a plugin change that is not accompanied by regenerated examples fails the build.
Regenerate with `rake sqlc_generate_process` (pure Ruby, fast) or `rake sqlc_generate_wasm` (builds the WASM first).

## End-to-end tests (`tests/`)
They `require` the generated code from `examples/` and run it against a real database, with Minitest.
`rbs_types.rb` additionally checks that returned values match the generated `.rbs` types.
* SQLite needs nothing: `rake end2end_sqlite3`.
* PostgreSQL / MySQL: provide a server, load `examples/authors/<db>/schema.sql`, and set `DB_NAME DB_USER DB_PASS
  POSTGRES_HOST MYSQL_HOST` (optionally `*_PORT`). MySQL needs `local_infile=1` for `:copyfrom`, and the MySQL tests
  connect without a password (`DB_PASS` is only used for PostgreSQL), so use a user without one.
  Or run everything in Docker: `rake run_end2end_tests` (docker-compose).
* They cover every query command (batches with encoded `bytea` / `json` values too), transactions (nested,
  isolation, `break` / `throw`, a rescued failed statement on PostgreSQL, SQLite threads sharing a database, the
  yielded `tx` used from other fibers / threads), models named like Ruby constants (`Exception`, `Data`, ...), pool
  injection, logging, bang finders, row members named like row methods (`initialize`), MySQL changed vs. matched
  rows, SQLite busy waiting, `:copyfrom` with awkward and binary values, lazy enumerators and its all-or-nothing behaviour,
  PostgreSQL `PREPARE`s interrupted after the server ran them, SQLite JSON / UUID text that looks numeric,
  Fiber-scheduler concurrency (`async` gem) and statement-leak checks.

## CI workflows (`.github/workflows/`)
| Workflow | When | What |
|---|---|---|
| `build.yml` | push to `main`, pull requests (not for Markdown-only changes), release | build `plugin.wasm`; lint; `sqlc diff` with the WASM and the process plugin; Steep; generate with option combinations (Ruby 3.1/3.2/3.3/4.0 × types/Gemfile) and check the output with the matching Ruby |
| `tests.yml` | same | unit tests; plugin compatibility on Ruby 3.1 / 3.2 / 3.4 / 4.0; full E2E matrix on Ruby 3.1 / 3.2 / 3.3 / 3.4 / 4.0; Ruby 4.0 module-name variants for MySQL and SQLite and module-name + no-prepared-statements variant for PostgreSQL; PostgreSQL 16.2, MySQL 8.3.0, and SQLite; generator-options E2E on Ruby 3.1 / 4.0 |
| `cross-platform.yml` | called by `build.yml` after `build-wasm` | macOS and Windows × Ruby 3.1 / 4.0 (oldest and newest supported), as two parallel jobs each. *Codegen*: unit + golden tests; `sqlc diff` with the Linux-built `plugin.wasm` and with the process plugin (`exe\plugin.cmd` on Windows); WASM codegen check. *End-to-End*: full E2E for SQLite, PostgreSQL (16 on macOS, 17 on Windows) and MySQL 8.4, installed natively (`ankane/setup-postgres`, `ankane/setup-mysql`, the image's MySQL on Windows), using the generated Gemfiles (installed gems cached per runner image); generator-options E2E |
| `docs.yml` | `examples/` change on `main`, manual | regenerates `docs/Examples.md` and opens a PR |
| `release.yml` | manual only | see [Releasing](Releasing.md) |

Tool versions (sqlc, ruby.wasm) live in `scripts/tool-versions.env`; dependabot updates actions and gems weekly.

## Before you push
```
bundle exec rake test rubocop steep
sqlc -f sqlc.local.yaml diff                                 # committed examples must be current
scripts/tests/run_codegen.rb sqlc.local.yaml 3.1 true true
rake end2end_sqlite3 end2end_pg end2end_mysql2               # full Ruby 3.1–4.0 matrix, plus Ruby 4.0 variants
BUNDLE_GEMFILE=Gemfile.options.e2e bundle exec ruby tests/end2end_options.rb # Ruby 3.1 and 4.0
```
CI also runs the unit suite without Bundler on Ruby 3.1 and 4.0. For Ruby 3.1/3.2 E2E, generate scratch examples
with their matching `rubyVersion` and install the generated Gemfile before running the suite.
