[![CI](https://github.com/DaredevilOSS/sqlc-gen-ruby/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/DaredevilOSS/sqlc-gen-ruby/actions/workflows/ci.yml)

# sqlc-gen-ruby
A [sqlc](https://sqlc.dev) plugin that generates Ruby code (plus optional RBS type signatures) from SQL.
Supported drivers: `pg`, `mysql2` and `sqlite3`.

The plugin itself is written in Ruby: it is pure Ruby with no native dependencies (it has its own tiny protobuf
codec), and it is shipped as a single self-contained WebAssembly module — the Ruby interpreter
([ruby.wasm](https://github.com/ruby/ruby.wasm)) with the plugin embedded. See [docs/Design.md](docs/Design.md).

## Usage

### Options Documentation
| Option          | Possible values                                | Optional | Info                                                                                                      |
|-----------------|------------------------------------------------|----------|-----------------------------------------------------------------------------------------------------------|
| driver          | values: `mysql2`,`pg`, `sqlite3`               | No       | Choosing the driver to use - see [here](docs/Examples.md) for more details info.                          |
| rubyVersion     | default: `3.3`<br/>values: `3.1`, `3.2`, `3.3` | Yes      | Determines the Ruby version the generated code should support..                                           |
| generateGemfile | default: `false`<br/>values: `false`,`true`    | Yes      | Assists you with the integration of SQLC and Ruby by generating a `Gemfile` with the needed dependencies. |
| generateTypes   | default: `true`<br/>values: `false`,`true`     | Yes      | Determines whether to generate type signatures in addition to the code.                                   |

### Configuration
```yaml
version: "2"
plugins:
- name: ruby
  wasm:
    url: https://github.com/DaredevilOSS/sqlc-gen-ruby/releases/download/${RELEASE_TAG}/sqlc-gen-ruby.wasm
    sha256: ${RELEASE_SHA}
sql:
  # PostgreSQL Example
  - schema: "examples/authors/postgresql/schema.sql"
    queries: "examples/authors/postgresql/query.sql"
    engine: "postgresql"
    codegen:
      - plugin: ruby
        out: examples/pg
        options:
          driver: pg
          rubyVersion: "3.3"
          generateTypes: true
          generateGemfile: false
  # MySQL Example
  - schema: "examples/authors/mysql/schema.sql"
    queries: "examples/authors/mysql/query.sql"
    engine: "mysql"
    codegen:
      - plugin: ruby
        out: examples/mysql2
        options:
          driver: mysql2
          rubyVersion: "3.3"
          generateTypes: true
          generateGemfile: false
  # Sqlite3 Example
  - schema: "examples/authors/sqlite/schema.sql"
    queries: "examples/authors/sqlite/query.sql"
    engine: "sqlite"
    codegen:
      - plugin: ruby
        out: examples/sqlite3
        options:
          driver: sqlite3
          rubyVersion: "3.3"
          generateTypes: true
          generateGemfile: false
```

### [Generated Code Examples](docs/Examples.md)

# Contributing
## Local plugin development
### Prerequisites
* Ruby 3.3 and `bundle install`
* [sqlc](https://docs.sqlc.dev/en/latest/overview/install.html) (v1.27.0 was used for verification)
* `curl` + `tar` for building the WASM plugin (it downloads the prebuilt ruby.wasm interpreter)
* Docker + docker-compose, for the end-to-end tests only (they need real MySQL / PostgreSQL servers)

### Layout
| Path | What |
|---|---|
| `exe/plugin.rb` | plugin entry point: `GenerateRequest` on stdin → `GenerateResponse` on stdout |
| `lib/sqlc_gen_ruby/` | the generator (`generator.rb`, `method_gen.rb`, `drivers/*.rb`, `options.rb`, ...) |
| `test/` | unit + golden tests (`rake test`); `test/fixtures` are real requests captured from sqlc |
| `tests/` | end-to-end tests of the generated code against real databases |
| `scripts/wasm/` | building the WASM plugin |

### Unit & golden tests
```
bundle exec rake test
```
The golden tests feed the plugin real `GenerateRequest`s captured from sqlc and diff the result against
[examples/](examples) (and against `test/golden`, recorded from the original C# implementation).
To refresh a fixture see `scripts/capture_request.rb`.

### Generating code
SQLC utilizes our process / WASM plugin to generate code
```
rake sqlc_generate_process   # runs exe/plugin.rb directly (needs `ruby` on PATH)
rake sqlc_generate_wasm      # builds dist/plugin.wasm first and runs that
```

### Testing generated code
Testing the SQLC generated code via a predefined flow:
```
rake test_process_plugin
rake test_wasm_plugin
```

### Building the WASM plugin
```
rake wasm_build   # == ./scripts/wasm/build.sh, writes dist/plugin.wasm (~18 MB)
```

## Release flow
The release flow in this repo follows the semver conventions, building tag as `v[major].[minor].[patch]`.

* In order to create a release you need to add `[release]` somewhere in your commit message when merging to master

### Version bumping (built on tags)
**By default, the release script will bump the patch version.**, by adding `[release]` to your commit message the release script will create a new tag with `v[major].[minor].[patch]+1`.
* Bump `minor` version by adding `[minor]` to your commit message resulting in a new tag with `v[major].[minor]+1.0`<br/>
* Bump `major` version by adding `[major]` to your commit message resulting in a new tag with `v[major]+1.0.0`

### Release structure
The new created tag will create a draft release with it, in the release there will be the wasm plugin embedded in the release.<br/>
> Publish the draft
