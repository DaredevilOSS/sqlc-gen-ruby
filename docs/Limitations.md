# Limitations

What to know before you adopt the plugin. Most of these come from sqlc or the databases, not from the plugin.

## All databases

* Two result columns with the same name (e.g. `a.id, b.id`) are an error: alias one (`b.id AS book_id`) or use
  `sqlc.embed`.
* `:batchexec` / `:batchone` / `:batchmany` are not atomic on their own: wrap them in `transaction` for all-or-nothing.
* Query names that would replace a generated method (`Transaction`, `Initialize`, ...) are errors.
* Large `sqlc.slice` arrays hit database limits (see SQLite and MySQL below). Load larger sets into a table
  (`:copyfrom`) and join it instead.
* Timestamps without a time zone store the local wall-clock time (see [Types](Types.md#time-zones)).

## PostgreSQL

* `sqlc.slice` is not offered by sqlc for PostgreSQL: use `= ANY($1::bigint[])` with an array.
* `:copyfrom` cannot express `ON CONFLICT` / `RETURNING`: those are generation errors, use `:batchexec`.
* `:execresult`'s `last_insert_id` is `nil`: use `RETURNING`.
* Behind pgbouncer in transaction mode set `preparedStatements: false` ([Options](Options.md#preparedstatements-pg)).

## MySQL

* `transaction` on a client inside a transaction that was started with raw SQL or by another library commits that
  transaction first (MySQL's `BEGIN` does), so a later `ROLLBACK` no longer undoes it. Run the outer work in
  `transaction` too (inner calls become savepoints), or finish the other transaction first.
* sqlc lowercases the table name that `sqlc.embed` expands to (`sqlc.embed(MixedItems)` becomes
  `SELECT mixeditems.itemid, ...`). MySQL table names are case-sensitive on Linux, so a mixed-case table fails with
  `Unknown column 'mixeditems.itemid'`. This is a sqlc limitation the plugin cannot undo (the request only carries the
  lowercased name); give the table an alias and embed that: `` SELECT sqlc.embed(m) FROM `MixedItems` AS m ``.
* A statement is limited by the server's `max_allowed_packet` (large `sqlc.slice` arrays).
* `:copyfrom` needs `local_infile` on client and server and commits an open raw-SQL transaction
  (see [Queries](Queries.md#copyfrom)).
* No server-side prepared statements: parameters are quoted client-side.

## SQLite

* A statement takes at most 32,766 parameters (`SQLITE_MAX_VARIABLE_NUMBER`), so a `sqlc.slice` with more elements
  raises `SQLite3::SQLException: too many SQL variables`.
* `NUMERIC` affinity can return an `Integer` where `Float` is declared.
* sqlc does not see parameters in `ON CONFLICT ... DO UPDATE SET` (it leaves `sqlc.arg(...)` in the SQL or reports
  fewer parameters than there are `?`), so such queries are generation errors. Use `excluded.<column>`
  (`DO UPDATE SET n = counters.n + excluded.n`) or move the value into `VALUES`.
* sqlc (1.27 – 1.31 at least) misplaces the SQL of a query file that contains a non-ASCII character (in a name,
  literal or comment): that query and the following ones lose characters at the end (`FROM user` instead of
  `FROM users`). This is a sqlc bug, not a plugin one; keep SQLite query files ASCII and pass such values as
  parameters.
* `busy_timeout=` makes the sqlite3 gem wait for a locked database while holding Ruby's GVL, so other threads and
  fibers stop too; `busy_handler_timeout=` waits without blocking them.
* Transactions belong to the thread that opened them; fibers sharing the same database take turns, and a transaction
  holds it until it ends. Only the yielded `tx` runs inside the transaction from other fibers / threads.
* sqlc before 1.30 reports quoted table names with their quotes (see [Names](Types.md#names)).

## Not applicable to Ruby

They exist in the C# plugin: `withAsyncSuffix` / `withCancellationToken` (use the Fiber scheduler), `useDapper`,
target framework / csproj options (`moduleName` replaces the namespace).
