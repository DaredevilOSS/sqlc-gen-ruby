[![CI](https://github.com/DaredevilOSS/sqlc-gen-ruby/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/DaredevilOSS/sqlc-gen-ruby/actions/workflows/ci.yml)

# sqlc-gen-ruby
Why I didn't use Ruby to generate Ruby in [here](ruby-wasm-poc/README.md).

## Usage
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
  # MySQL Example
  - schema: "examples/authors/mysql/schema.sql"
    queries: "examples/authors/mysql/query.sql"
    engine: "mysql"
    codegen:
      - plugin: ruby
        out: examples/mysql2
        options:
          driver: mysql2
```

### Options Documentation
| Option          | Possible values                                | Optional | Info                                                                                                        |
|-----------------|------------------------------------------------|----------|-------------------------------------------------------------------------------------------------------------|
| driver          | <br/>values: `mysql2`,`pg`                     | No       | Choosing the driver to use - refer to the [above](#supported-sql-engines) section on supported SQL engines. |
| rubyVersion     | default: `3.3`<br/>values: `3.1`, `3.2`, `3.3` | Yes      | Determines the Ruby version the generated code should support..                                             |
| generateGemfile | default: `false`<br/>values: `false`,`true`    | Yes      | Assists you with the integration of SQLC and Ruby by generating a `Gemfile` with the needed dependencies.   |

### [Generated Code Examples](docs/Examples.md)

### Next features
1. Supporting sqlite engine, utilizing sqlite3 gem
2. Adding type support to generated code by generating .rbs files

# Contributing
## Local plugin development
### Prerequisites
make sure that the following applications are installed and exposed in your path

Follow the instructions in each of these:
* Ruby - [Ruby Installation](https://www.ruby-lang.org/en/downloads/)
* Dotnet CLI - [Dotnet Installation](https://github.com/dotnet/sdk) - use version `.NET 8.0 (latest)`
* buf build - [Buf Build](https://buf.build/docs/installation)
* WASM related - [WASM libs](https://www.strathweb.com/2023/09/dotnet-wasi-applications-in-net-8-0/)

### Protobuf
SQLC protobuf are defined in sqlc-dev/sqlc repository.
Generating Ruby code from protocol buffer files:
```
rake protobuf_generate
```

### Generating code
SQLC utilizes our process / WASM plugin to generate code
```
rake sqlc_generate_process
rake sqlc_generate_wasm
```

### Testing generated code
Testing the SQLC generated code via a predefined flow:
```
rake test_process_plugin
rake test_wasm_plugin
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
