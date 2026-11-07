# Troubleshooting

Something failed or looks odd? Find it here. Most of these come from sqlc or the databases, not from the plugin.

## Any database

| You see | Why | Do this |
|---|---|---|
| Generation error: two result columns with the same name (`a.id, b.id`) | a row has one member per name | alias one (`b.id AS book_id`) or use `sqlc.embed` |
| Generation error: a query named `Transaction`, `Initialize`, ... | it would replace a generated method | rename the query |
| Half the rows of a batch were written before an error | `:batchexec` / `:batchone` / `:batchmany` are not atomic on their own | wrap them in `transaction` |
| A timestamp comes back one hour off around a daylight-saving change | `timestamp` / `DATETIME` store the local wall-clock time, so the repeated hour is ambiguous | use `timestamptz` / `TIMESTAMP`, or run the process in UTC (`TZ=UTC`), see [Types](Types.md#time-zones) |
| A huge `sqlc.slice` fails | database limits (SQLite and MySQL below) | `:copyfrom` the values into a table and join it |

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
| A rollback did not undo work done before `transaction` | `transaction` on a client inside a transaction started with raw SQL or by another library commits it first (MySQL's `BEGIN` does) | run the outer work in `transaction` too (inner calls become savepoints), or finish the other transaction first |
| `Unknown column 'mixeditems.itemid'` with `sqlc.embed(MixedItems)` | sqlc lowercases the table name it expands to, and MySQL table names are case-sensitive on Linux; the plugin only receives the lowercased name | give the table an alias and embed that: `` SELECT sqlc.embed(m) FROM `MixedItems` AS m `` |
| `:copyfrom` is refused / fails | `LOAD DATA LOCAL INFILE` needs `local_infile` | `local_infile: true` in the `Mysql2::Client` params and `local_infile=1` on the server, see [Queries](Queries.md#copyfrom) |
| A `sqlc.slice` fails with a packet error | the statement exceeds the server's `max_allowed_packet` | `:copyfrom` into a table and join it |
| `:execrows` counts changed rows, not matched rows | MySQL's default | connect with `flags: Mysql2::Client::FOUND_ROWS` |
| `:copyfrom` committed my raw-SQL transaction | `LOAD DATA` commits an open `BEGIN` transaction | call `:copyfrom` inside `transaction` |

MySQL does not use server-side prepared statements: parameters are quoted client-side with `Mysql2::Client#escape`
and sent with `Client#query`.

## SQLite

| You see | Why | Do this |
|---|---|---|
| Queries lose their last characters (`FROM user` instead of `FROM users`) | sqlc (1.27 – 1.31 at least) misplaces the SQL of a query file that contains a non-ASCII character in a name, literal or comment. A sqlc bug, not a plugin one | keep SQLite query files ASCII and pass such values as parameters |
| Generation error with `sqlc.arg(...)` in `ON CONFLICT ... DO UPDATE SET` | sqlc does not see parameters there (it leaves `sqlc.arg(...)` in the SQL or reports fewer parameters than there are `?`) | use `excluded.<column>` (`DO UPDATE SET n = counters.n + excluded.n`) or move the value into `VALUES` |
| `SQLite3::SQLException: too many SQL variables` | a statement takes at most 32,766 parameters (`SQLITE_MAX_VARIABLE_NUMBER`) | `:copyfrom` into a table and join it |
| An `Integer` where `Float` is declared | `NUMERIC` affinity | cast in the query or use `overrides` |
| Other threads freeze while the database is locked | `busy_timeout=` waits while holding Ruby's GVL | use `busy_handler_timeout=`, which waits without blocking them |
| A fiber or thread waits for a transaction | SQLite transactions belong to the thread that opened them; fibers sharing a database take turns, and a transaction holds it until it ends | use the yielded `tx` inside the transaction |
| The model is named `Items` instead of `Item` | sqlc before 1.30 (including the pinned 1.27) reports a quoted table name with its quotes | `rename` or `exactTableNames`, see [Names](Types.md#names) |
| Steep complains about `Monitor` / `Timeout` | the generated code uses them | add `library "monitor"` (and `library "timeout"` for `rubyVersion` below 3.3) to your `Steepfile` |

## Options from the C# plugin

`withAsyncSuffix` / `withCancellationToken` (use the Fiber scheduler), `useDapper` and the target framework / csproj
options do not apply to Ruby; `moduleName` replaces the namespace.
