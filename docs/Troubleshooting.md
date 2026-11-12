# Troubleshooting

Known errors and surprises, with their cause and fix. Most of them come from sqlc or from the database itself, not
from the plugin.

## Any database

| You see | Why | Do this |
|---|---|---|
| Generation error: two result columns with the same name (`a.id, b.id`) | a row has one member per name | alias one (`b.id AS book_id`) or use `sqlc.embed` |
| Generation error: a query named `Transaction`, `Initialize`, ... | it would replace a generated method | rename the query |
| Half the rows of a batch were written before an error | `:batchexec` / `:batchone` / `:batchmany` are not atomic on their own | wrap them in `transaction` |
| A timestamp comes back one hour off around a daylight-saving change | `timestamp` / `DATETIME` store the local wall-clock time, so the repeated hour is ambiguous | use `timestamptz` / `TIMESTAMP`, or run the process in UTC (`TZ=UTC`), see [Types](Types.md#dates-and-time-zones) |
| A huge `sqlc.slice` fails | database limits (see MySQL and SQLite below) | `:copyfrom` the values into a table and join it |
| `break` / `return` inside `transaction` rolls back | Ruby below 3.3 with its bundled `timeout` gem | `gem 'timeout', '>= 0.4'`, see [Transactions](Transactions.md#ruby-below-33-with-timeout--04) |
| Steep cannot find `Monitor` / `Timeout` | the generated code uses them (`Monitor` on SQLite, `Timeout` for a `rubyVersion` below 3.3) | add `library "monitor"` / `library "timeout"` to your `Steepfile` |

## PostgreSQL

| You see | Why | Do this |
|---|---|---|
| `sqlc.slice` is not available | sqlc does not offer it for PostgreSQL | `WHERE id = ANY($1::bigint[])` with an array |
| Prepared statement errors behind pgbouncer in transaction mode | statements are prepared per connection | `preparedStatements: false` ([Options](Options.md#preparedstatements-pg)) |
| Generation error in a `:copyfrom` query with `ON CONFLICT` / `RETURNING` | `COPY` cannot express them | use `:batchexec` |
| `last_insert_id` of `:execresult` is `nil` | PostgreSQL has no last-insert id | use `RETURNING` (`:one` or `:execlastid`) |

## MySQL

| You see | Why | Do this |
|---|---|---|
| A rollback did not undo work done before `transaction` | `transaction` on a client inside a transaction started with raw SQL or by another library commits it first (MySQL's `BEGIN` does) | run the outer work in `transaction` too (inner calls become savepoints), or finish the other transaction first, see [Transactions](Transactions.md#inside-another-librarys-transaction) |
| `Unknown column 'mixeditems.itemid'` with `sqlc.embed(MixedItems)` | sqlc lowercases the table name it expands to, and MySQL table names are case-sensitive on Linux; the plugin only receives the lowercased name | give the table an alias and embed that: `` SELECT sqlc.embed(m) FROM `MixedItems` AS m `` |
| `:copyfrom` is refused / fails | `LOAD DATA LOCAL INFILE` needs `local_infile` | `local_infile: true` in the `Mysql2::Client` params and `local_infile=1` on the server, see [Queries](Queries.md#copyfrom) |
| A `sqlc.slice` fails with a packet error | the statement exceeds the server's `max_allowed_packet` | `:copyfrom` into a table and join it |
| `:execrows` counts changed rows, not matched rows | MySQL's default | connect with `flags: Mysql2::Client::FOUND_ROWS` |
| `:copyfrom` committed my raw-SQL transaction | `LOAD DATA` commits an open `BEGIN` transaction | call `:copyfrom` inside `transaction` |

## SQLite

| You see | Why | Do this |
|---|---|---|
| Queries lose their last characters (`FROM user` instead of `FROM users`) | sqlc (1.27 – 1.31 at least) misplaces the SQL of a query file that contains a non-ASCII character in a name, literal or comment. A sqlc bug, not a plugin one | keep SQLite query files ASCII and pass such values as parameters |
| Generation error with `sqlc.arg(...)` in `ON CONFLICT ... DO UPDATE SET` | sqlc does not see parameters there (it leaves `sqlc.arg(...)` in the SQL or reports fewer parameters than there are `?`) | use `excluded.<column>` (`DO UPDATE SET n = counters.n + excluded.n`) or move the value into `VALUES` |
| `SQLite3::SQLException: too many SQL variables` | a statement takes at most 32,766 parameters (`SQLITE_MAX_VARIABLE_NUMBER`) | `:copyfrom` into a table and join it |
| An `Integer` where `Float` is declared | `NUMERIC` affinity: SQLite stores `5.0` as `5` | call `to_f` on the value, or declare the column `Numeric` with [`overrides`](Options.md#overrides) |
| Other threads freeze while the database is locked | `busy_timeout=` waits while holding Ruby's GVL | use `busy_handler_timeout=`, which waits without blocking them |
| A fiber or thread waits for a transaction | a SQLite transaction holds the database until it ends, and belongs to the thread that opened it | keep transactions short; inside one, use the yielded `tx` from other fibers / threads |
| The model is named `Items` instead of `Item` | sqlc before 1.30 (including the pinned 1.27) reports a quoted table name with its quotes | `rename` or `exactTableNames`, see [Names](Generated-Code.md#names) |

## Coming from sqlc-gen-csharp

These options of the C# plugin do not exist here: `withAsyncSuffix` / `withCancellationToken` (use the Fiber scheduler), `useDapper` and the target
framework / csproj options. `moduleName` replaces the namespace option.
