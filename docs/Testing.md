# Testing and CI

## The rules

* Every documented behavior (README and `docs/`) needs an end-to-end test against a real database, for each database
  it applies to, and a row in [Coverage](Coverage.md).
* A bug fix starts with an end-to-end test that fails before the fix.
* Unit tests are for what end-to-end tests cannot reach: option validation and generation errors.

## The layers

Each layer answers a different question, and each runs in CI.

| Layer | Command | Needs | Question |
|---|---|---|---|
| Unit + golden | `bundle exec rake test` | nothing | does the plugin produce the expected files? |
| Generated-code checks | `bundle exec rake rubocop steep` | nothing | is the generated code clean Ruby with correct types? |
| `sqlc diff` | `sqlc -f sqlc.local.yaml diff` | sqlc | do the committed `examples/` match what the plugin generates now? |
| End-to-end | `rake end2end_sqlite3 end2end_pg end2end_mysql2` | databases | does the generated code behave correctly against a real database? |

### Unit and golden tests (`test/`)

| File | What it checks |
|---|---|
| `golden_test.rb` | runs the plugin on real requests captured from sqlc (`test/fixtures/*.bin`) and compares with the committed `examples/` |
| `extended_golden_test.rb` | the same for option variants (Ruby 3.1 / 3.2, no types, `generateGemfile`, ...) and synthetic requests (`synthetic_requests.rb`), against `test/golden/` |
| `features_test.rb`, `options_test.rb` | one focused test per feature or option |
| `codec_test.rb` | the hand-written protobuf codec against Google's `google-protobuf` (a test-only gem) |
| `coverage_map_test.rb` | every test linked from [Coverage](Coverage.md) exists |

* After an intended output change, rewrite the golden files and **read the diff**:
  `UPDATE_GOLDEN=1 bundle exec ruby -Itest test/extended_golden_test.rb`
* After a new sqlc version or a schema change, refresh the fixtures with `scripts/capture_request.rb` (see its header).

### `examples/` and `sqlc diff`

`examples/authors/<engine>/{schema,query}.sql` are the inputs. `examples/<driver>/` is the plugin's output, committed.
CI runs `sqlc diff` against it with both the process plugin and the WASM, so a plugin change without regenerated
examples fails the build.

Regenerate with `rake sqlc_generate_process` (pure Ruby, fast) or `rake sqlc_generate_wasm` (builds the WASM first).

### End-to-end tests (`tests/`)

Minitest suites that `require` the generated code from `examples/` and run it against a real database.
`rbs_types.rb` also checks that returned values match the generated `.rbs` types.

| Suite | Needs |
|---|---|
| `rake end2end_sqlite3` | nothing |
| `rake end2end_pg` | a PostgreSQL server with `examples/authors/postgresql/schema.sql` loaded |
| `rake end2end_mysql2` | a MySQL server with `examples/authors/mysql/schema.sql` loaded and `local_infile=1` (for `:copyfrom`) |
| `tests/end2end_options.rb` | sqlc and PostgreSQL; generates code with other options and runs it (PostgreSQL, SQLite) |
| `rake run_end2end_tests` | Docker: starts the servers with docker-compose and runs the suites |

The servers are configured with `DB_NAME`, `DB_USER`, `DB_PASS`, `POSTGRES_HOST`, `MYSQL_HOST` (and optionally
`*_PORT`). The MySQL tests connect without a password (`DB_PASS` is only used for PostgreSQL), so use a MySQL user
that has none.

What each test proves is listed in [Coverage](Coverage.md).

## CI workflows (`.github/workflows/`)

Every job has `timeout-minutes: 10`. Pull requests need `build.yml` and `tests.yml` green; both skip Markdown-only
changes.

| Workflow | Runs on | What |
|---|---|---|
| `build.yml` | pull requests, pushes to `main`, releases | builds `plugin.wasm`; lint; `sqlc diff` with the WASM and with the process plugin; Steep; the option matrix; then calls `cross-platform.yml` |
| `tests.yml` | the same | unit tests; plugin compatibility; the end-to-end matrix |
| `cross-platform.yml` | called by `build.yml` | the Linux-built WASM, the process plugin and all end-to-end suites on macOS and Windows |
| `docs.yml` | changes of `examples/authors/` or `sqlc.ci.yaml` on `main`, manually | regenerates `docs/Examples.md` and opens a pull request |
| `release.yml` | manually | see [Releasing](Releasing.md) |

**`build.yml` option matrix:** generates with combinations of `rubyVersion` (3.1, 3.2, 3.3, 4.0), `generateTypes` and
`generateGemfile`, and checks the output with the matching Ruby.

**`tests.yml`:**

| Job | Matrix |
|---|---|
| Unit tests | Ruby 3.3 |
| Plugin compatibility | the plugin itself on Ruby 3.1, 3.2, 3.4, 4.0 |
| End-to-end | Ruby 3.1, 3.2, 3.3, 3.4, 4.0 × PostgreSQL 16.2, MySQL 8.3.0, SQLite |
| End-to-end variants | Ruby 4.0 with a custom `moduleName` (all three), plus `preparedStatements: false` on PostgreSQL; Ruby 3.1 on PostgreSQL with Ruby's bundled timeout 0.2.0 (`E2E_TIMEOUT_GEM`, `Gemfile.e2e`) |
| Generator options end-to-end | Ruby 3.1 and 4.0 |

**`cross-platform.yml`:** macOS and Windows × Ruby 3.1 and 4.0 (the oldest and newest supported), two jobs each.

* *Codegen:* unit and golden tests; `sqlc diff` with the Linux-built `plugin.wasm` and with the process plugin
  (`exe\plugin.cmd` on Windows); a WASM codegen check.
* *End-to-End:* all suites against natively installed databases (PostgreSQL 16 on macOS and 17 on Windows, MySQL 8.4,
  SQLite), using the generated Gemfiles.

Dependabot updates actions and gems weekly; tool versions (sqlc, ruby.wasm) are pinned in `scripts/tool-versions.env`.

## Before you push

```
bundle exec rake test rubocop steep
sqlc -f sqlc.local.yaml diff                                 # committed examples must be current
scripts/tests/run_codegen.rb sqlc.local.yaml 3.1 true true   # generate for Ruby 3.1 with types + Gemfile, check it
rake end2end_sqlite3 end2end_pg end2end_mysql2
BUNDLE_GEMFILE=Gemfile.options.e2e bundle exec ruby tests/end2end_options.rb
```

To run the end-to-end suites for Ruby 3.1 / 3.2 locally, generate scratch examples with the matching `rubyVersion`
(`ruby scripts/tests/generate_examples.rb 3.1 sqlc.local.yaml --generate-gemfile`), point `EXAMPLES_DIR` at the
`.examples-ruby-3.1` directory it writes, and install the generated Gemfile first.
