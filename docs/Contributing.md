# Contributing

Contributions are welcome. This page gets you set up; the other contributor docs go deeper.

| Doc | What |
|---|---|
| [Architecture](Architecture.md) | how the generator works, the WASM packaging, adding a feature / option / driver |
| [Testing](Testing.md) | the test layers, CI workflows, what to run before pushing |
| [Coverage](Coverage.md) | every documented behavior mapped to its end-to-end test |
| [Releasing](Releasing.md) | the release workflow and versioning rules |
| [CLAUDE.md](../CLAUDE.md) | the same orientation, condensed for AI coding assistants |

## Setup

You need:

* Ruby 3.3 and `bundle install`;
* [sqlc](https://docs.sqlc.dev/en/latest/overview/install.html), in the version pinned in
  [`scripts/tool-versions.env`](../scripts/tool-versions.env);
* `curl` and `tar` to build the WASM;
* PostgreSQL and MySQL servers, or Docker, for the end-to-end tests.

## Commands

```
bundle exec rake test                 # unit + golden tests (no database needed)
bundle exec rake rubocop steep        # the generated code must stay RuboCop- and Steep-clean
rake sqlc_generate_process            # regenerate examples/ with exe/plugin.rb
rake sqlc_generate_wasm               # build dist/plugin.wasm, then regenerate examples/ with it
rake end2end_sqlite3                  # end-to-end, no server needed
rake end2end_pg end2end_mysql2        # end-to-end, needs servers (see Testing.md)
rake run_end2end_tests                # end-to-end in Docker (docker-compose)
```

## Making a change

* **Generated output:** `examples/` is the plugin's committed output and CI fails when it drifts. When a change alters
  the generated code, regenerate `examples/` and the golden files in the same commit, and read their diff.
* **Tests:** new behavior and bug fixes come with an end-to-end test and a row in [Coverage](Coverage.md).
* **Docs:** user-facing behavior is documented in `docs/`; the README stays a short overview that links there.
* **Pull requests** target `main`, need both CI workflows (`build.yml`, `tests.yml`) green, and get a label: `bug`,
  `enhancement` or `documentation` (`breaking` for incompatible changes).

Releases are started by a maintainer and automated from there: see [Releasing](Releasing.md).
