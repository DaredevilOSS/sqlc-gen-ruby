# The generated code

For each query file you get `query_sql.rb` with a `QuerySql` class (one method per query; the file name in CamelCase:
`admin_users.sql` → `AdminUsersSql` in `admin_users_sql.rb`), plus:

* `models.rb`: one class per table, one module of constants per enum,
* `connection.rb`: shared helpers,
* the matching `.rbs` files (unless `generateTypes: false`), and a `Gemfile` with `generateGemfile: true`.

See [Examples](Examples.md) for the real output of every driver.

## Rows

Frozen `Data` objects from Ruby 3.2 (with `with` and `to_h`) or mutable keyword `Struct`s below Ruby 3.2; both support
pattern matching:

```ruby
case row
in { id:, name: } then ...
end
```

## Arguments and finders

* Arguments are keywords named after the parameters: see [Queries](Queries.md#arguments).
* **Bang finders:** every `:one` query also gets a `get_author!` that raises `QuerySql::NotFound` instead of returning
  `nil`.

## Logging

`connect(params, logger: Rails.logger)` / `new(pool, logger:)` logs `QuerySql#get_author (0.4ms)` at debug level for
each query and transaction. Parameter values are never logged.

## Style

* SQL lives in frozen heredoc constants (`GET_AUTHOR_SQL`).
* Comments above a query become its doc comment; table / column / enum comments of the schema become doc comments of
  the models.
* The code is RuboCop-clean. Where a name from your schema breaks a RuboCop naming rule (`"UserId"`, `naïve`), that
  class or method gets a `rubocop:disable` (on SQLite keep the query files ASCII, see [Troubleshooting](Troubleshooting.md)).
  Query names such as `HasAuthors` / `IsActive` keep their name (`has_authors`) with `Naming/PredicatePrefix` disabled.

## More

* [Transactions and connections](Transactions.md): `transaction`, pools, forks, Async.
* [Types and names](Types.md).
