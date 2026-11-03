# Testing and CI

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
  isolation, `break` / `throw`, a rescued failed statement on PostgreSQL, SQLite threads sharing a database), pool
  injection, logging, bang finders, `:copyfrom` with awkward and binary values and its all-or-nothing behaviour,
  Fiber-scheduler concurrency (`async` gem) and statement-leak checks.

## CI workflows (`.github/workflows/`)
| Workflow | When | What |
|---|---|---|
| `build.yml` | push to `main`, pull requests (not for Markdown-only changes), release | build `plugin.wasm`; lint; `sqlc diff` with the WASM and the process plugin; Steep; generate with option combinations (Ruby 3.1/3.2/3.3 × types/Gemfile) and check the output with the matching Ruby |
| `tests.yml` | same | unit tests; the plugin on Ruby 3.1 / 3.2 / 3.4; end-to-end against PostgreSQL 16 and MySQL 8.3 service containers and SQLite |
| `docs.yml` | `examples/` change on `main`, manual | regenerates `docs/Examples.md` and opens a PR |
| `release.yml` | manual only | see [Releasing](Releasing.md) |

Tool versions (sqlc, ruby.wasm) live in `scripts/tool-versions.env`; dependabot updates actions and gems weekly.

## Before you push
```
bundle exec rake test rubocop steep
rake sqlc_generate_process && git status --short examples   # must show no changes (or commit them)
rake end2end_sqlite3                                         # plus pg / mysql2 when the generated code changed
```
