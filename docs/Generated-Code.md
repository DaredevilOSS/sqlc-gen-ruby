# The generated code

What `sqlc generate` writes, and how the classes, methods and attributes are named.
The real output for every database is in [Examples](Examples.md).

## Files

| File | Contents |
|---|---|
| `query_sql.rb` | one per query file: the `QuerySql` class (one method per query) and the row classes of its queries. The names follow the file: `admin_users.sql` → `AdminUsersSql` in `admin_users_sql.rb` |
| `models.rb` | one class per table, one module of constants per enum |
| `connection.rb` | helpers the query classes share |
| `*.rbs` | signatures for each of the above (unless `generateTypes: false`) |
| `Gemfile` | the gems the code needs (only with `generateGemfile: true`) |

Everything lives in one module: `PgCodegen`, `Mysql2Codegen` or `Sqlite3Codegen`, or the
[`moduleName`](Options.md) you set.

## The query class

```ruby
queries = PgCodegen::QuerySql.connect({ dbname: 'app' }, size: 5)   # see Connections

queries.get_author(id: 1)      # => #<data PgCodegen::GetAuthorRow ...> or nil
queries.get_author!(id: 1)     # raises PgCodegen::QuerySql::NotFound instead of returning nil
queries.list_authors           # => [#<data PgCodegen::ListAuthorsRow ...>, ...]
```

* One method per query, named after it in snake_case. What it returns depends on the query's annotation: see
  [Queries](Queries.md).
* Arguments are keywords: see [Arguments](Queries.md#arguments).
* Every `:one` query also gets a bang method (`get_author!`) that raises `QuerySql::NotFound` when there is no row.
* `transaction`, `connect` and `new` are described in [Transactions](Transactions.md) and [Connections](Connections.md).

## Rows and models

A query returns `<Query>Row` objects (`GetAuthorRow`); `sqlc.embed` and `models.rb` use one class per table (`Author`).

| `rubyVersion` | Rows are | |
|---|---|---|
| 3.2 and later | `Data` | frozen; `with` and `to_h` |
| below 3.2 | keyword `Struct` | mutable |

Both support pattern matching:

```ruby
case queries.get_author(id: 1)
in { id:, name: } then puts "#{id}: #{name}"
in nil then puts 'no such author'
end
```

## Names

**Methods and arguments**

* Query names and parameters are snake_cased, with acronyms kept together (`MIN_ID` → `min_id`, `HTTPServer` →
  `http_server`).
* A Ruby keyword gets a trailing `_` as an argument (`end_:`).
* A parameter used twice is one keyword when it is named with `sqlc.arg`; repeated `?` / `$n` of one column become
  `id:`, `id_2:`.
* A query whose name would replace a generated method (`Transaction`, `Initialize`, ...) is a generation error.

**Row attributes**

* An attribute has the column's name as sqlc reports it: PostgreSQL and SQLite keep `"camelCase"` as `camelCase`, MySQL
  reports `camelcase`.
* A result column without a usable name (`SELECT 1, now()`) is named by its position: `column_1`, `column_2`, ...
* A name that would replace a method of the row gets a trailing `_` (`class_`, `hash_`, `initialize_`). `Struct` rows
  have more methods than `Data` rows, so a column `count` is `count` from `rubyVersion` 3.2 and `count_` below: check
  the generated `.rbs` when you change `rubyVersion`.
* Keywords are fine as attributes: a column `end` is the attribute `end`, but the argument `end_:`.

**Models**

* A table's model is its singular name (`authors` → `Author`). A table `authors` next to a table `author` keeps the
  plural (`Authors`). Change this with [`rename` or `exactTableNames`](Options.md).
* A model may have the name of a Ruby or driver constant (tables `exceptions`, `data`, `threads`, `sets`, ...). The
  generated code refers to the originals as `::Exception`, `::Data`, `::Thread`, ..., so the models never shadow them.
* SQLite: sqlc before 1.30 reports a quoted table name with its quotes, so `CREATE TABLE "Items"` gives the model
  `Items` there and `Item` from sqlc 1.30 on. Use `rename` or `exactTableNames` to keep the name when you upgrade sqlc.

Enum constants are described in [Types](Types.md#enums).

## Logging

Pass a logger (anything with `#debug`) and every query and transaction is logged at debug level with its name and
duration, for example `PgCodegen::QuerySql#get_author (0.4ms)`:

```ruby
PgCodegen::QuerySql.connect(params, logger: Rails.logger)
PgCodegen::QuerySql.new(pool, logger: Rails.logger)
```

Parameter values are never logged.

## Style and static checks

* The SQL of each query is a frozen heredoc constant (`GET_AUTHOR_SQL`).
* A comment above a query becomes the doc comment of its method. Table, column and enum comments of the schema become
  doc comments of the models.
* **RuboCop:** the code is RuboCop-clean. Where a name from your schema breaks a naming rule (`"UserId"`, `naïve`),
  that class or method gets a `rubocop:disable`. Query names such as `HasAuthors` / `IsActive` keep their name
  (`has_authors`), with `Naming/PredicatePrefix` disabled.
* **Steep:** the `.rbs` files type-check with Steep. Add the standard libraries the code uses to your `Steepfile`:
  `library "monitor"` for SQLite, and `library "timeout"` for a `rubyVersion` below 3.3. This repository's
  [`Steepfile`](../Steepfile) shows the full list for all three drivers.
