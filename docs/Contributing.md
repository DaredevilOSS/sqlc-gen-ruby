# Contributing

You need Ruby 3.3 (`bundle install`), [sqlc](https://docs.sqlc.dev/en/latest/overview/install.html) (version in
[`scripts/tool-versions.env`](../scripts/tool-versions.env)), `curl` + `tar` to build the WASM, and PostgreSQL / MySQL
servers (or Docker) for the end-to-end tests.

```
bundle exec rake test                 # unit + golden tests (no database needed)
bundle exec rake rubocop steep        # the generated code must stay RuboCop- and Steep-clean
rake sqlc_generate_process            # regenerate examples/ with exe/plugin.rb
rake sqlc_generate_wasm               # build dist/plugin.wasm, then regenerate examples/ with it
rake end2end_sqlite3                  # end-to-end, no server needed
rake end2end_pg end2end_mysql2        # end-to-end, needs servers (see Testing.md)
rake run_end2end_tests                # all of it in Docker (docker-compose)
```

`examples/` is the plugin's committed output and CI fails when it drifts, so regenerate it with every change to the
generated code. Pull requests need both CI workflows (`build.yml`, `tests.yml`) green.

Releases are started by a maintainer (**Actions → Release → Run workflow**) and are automated from there: the full test
gate, the tag, the GitHub release with the tested `sqlc-gen-ruby.wasm` and its sha256, and a check of the published file.

| Doc | What |
|---|---|
| [Architecture.md](Architecture.md) | how the generator works, where to change what, adding a feature / driver / option |
| [Testing.md](Testing.md) | the test layers, CI workflows, what to run before pushing |
| [Releasing.md](Releasing.md) | the release process and versioning rules |
| [Design.md](Design.md) | the WASM packaging and design decisions |
| [Coverage.md](Coverage.md) | every documented behavior mapped to its end-to-end test |
| [../CLAUDE.md](../CLAUDE.md) | the same orientation condensed for AI coding assistants |
