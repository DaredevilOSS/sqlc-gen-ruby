# Transactions and connections

```ruby
queries.transaction(isolation: :serializable) do |tx|
  id = tx.create_author_return_id(name: 'a', bio: nil)
  tx.transaction { tx.create_book(name: 'b', author_id: id) }  # nested: a SAVEPOINT
  :done                                                         # the block's value is returned
end
```

## The basics

* Everything in the block runs on one connection. It commits when the block ends (also on `break`, `return`, `throw`)
  and rolls back when it raises or the thread is killed. A nested `transaction` is a savepoint and rolls back only its
  own part.
* `isolation:` (`pg`, `mysql2`) takes `:read_uncommitted`, `:read_committed`, `:repeatable_read`, `:serializable`;
  `mode:` (`sqlite3`) takes `:deferred`, `:immediate`, `:exclusive`. Other values raise `ArgumentError` before anything
  runs, and so do `isolation:` / `mode:` on a nested `transaction` (a savepoint cannot change them).
* `tx` is a copy of the query object bound to the transaction: its queries stay in the transaction from any fiber or
  thread (an `Enumerator`, an `Async` task, a `Thread`), one at a time, and raise `TransactionEnded` once the
  transaction is over. Other query objects (the parent `queries`, another generated class sharing the pool) used from
  another fiber or thread check out their own connection and run outside the transaction: pass `tx` instead.
* With `connection_pool` or SQLite, parent-object calls from the same thread reuse the transaction connection;
  injected `#with` objects must do the same.
* A `transaction` inside a transaction that another library opened on the same connection (`BEGIN`) is a savepoint on
  PostgreSQL and SQLite. MySQL has no nested transactions: its `BEGIN` commits the open transaction first (see
  [Troubleshooting](Troubleshooting.md)).

## When something goes wrong

### Errors inside the block

* **PostgreSQL:** if a statement fails and the block rescues the error, PostgreSQL still rolls the whole transaction
  back, so `transaction` raises `PG::InFailedSqlTransaction` instead of pretending it committed. In a nested
  `transaction` only the savepoint is rolled back: the outer block can rescue that error and go on.
* **MySQL:** a deadlock (or a lock wait timeout with `innodb_rollback_on_timeout`) rolls the whole transaction back on
  the server, its savepoints too. If the block rescues that error, every later query in the transaction and
  `transaction` itself raise it again (a `Mysql2::Error` with the same `error_number`, its message prefixed with
  `transaction rolled back:`) instead of running in autocommit mode and reporting a commit; retry the whole
  `transaction`. A lock wait timeout without that setting fails only its statement: the block can rescue it and go on.
* **SQLite:** threads and fibers sharing one `SQLite3::Database` take turns; a transaction holds the database until it
  ends.

### Interrupts (`Timeout`, `Thread#raise`, `Thread#kill`, a stopped `Async` task)

* An interrupt that arrives while `BEGIN`, `COMMIT` or `ROLLBACK` runs waits for it to finish, and a `BEGIN` /
  `COMMIT` that raises itself (a stopped `Async` task) is rolled back: the connection never goes back to the pool
  inside a transaction.
* **PostgreSQL:** a query interrupted by any of them (inside or outside a transaction) is cancelled at once, so the
  connection goes back to the pool idle and a killed transaction rolls back without waiting for its query.
* **MySQL:** a `Thread#kill` during a query closes that client (mysql2 cannot send `ROLLBACK` while it waits for the
  query's result), so the server rolls the transaction back and the pool replaces the client.
* **Ruby < 3.3 with timeout < 0.4:** `break`, `return` and `throw` also roll back because Timeout cannot be told
  apart; add `gem 'timeout', '>= 0.4'` to the generated Gemfile to keep those exits committing. An old `Timeout` that
  interrupts a PostgreSQL query in a transaction still raises `Timeout::Error` (not the `PG::InFailedSqlTransaction`
  of the cancelled query) after rolling back.

### Lost connections

A connection the server closed (restart, failover, killed backend) is reconnected (`pg`) or replaced in the pool
(`mysql2`) the next time it is checked out; the call that hit the dead connection still raises. Inside `transaction` a
lost `pg` connection is not reconnected: every later call in the block and `transaction` itself raise
`PG::ConnectionBad`, so nothing after the loss runs outside the transaction (the server rolled it back). A `mysql2`
client that mysql2 closed because a running query was interrupted (an `Async` task stopped, `Thread#raise`) is
replaced the same way, without failing the next call.

## Connections

* `QuerySql.connect(params, **pool_options)` builds a [`connection_pool`](https://github.com/mperham/connection_pool).
  To use a pool you already have (or a fake in tests) pass it to `QuerySql.new(pool)`; anything with `#with` works.
* `pg`: `QuerySql.connect` also takes a connection URL: `QuerySql.connect(ENV.fetch('DATABASE_URL'), size: 5)`.
* SQLite: pass a `SQLite3::Database` (opened with any options, `results_as_hash: true` included): `QuerySql.new(db)`.
  SQLite transactions belong to the thread that opened them; fibers sharing the same database take turns, and a
  transaction holds it until it ends. Only the yielded `tx` runs inside the transaction from other fibers / threads.
* **Shared with another library** (ActiveRecord's `raw_connection`, Sequel, your own code): the connection keeps its
  settings. The generated queries pass their own type maps (`pg`; the connection's `type_map_for_results`,
  `type_map_for_queries` and `field_name_type` are left as they are) or query options (`mysql2`: rows are read with
  `as: :array, cast: true, cast_booleans: false`, whatever the client's or `Mysql2::Client.default_query_options`).
  On SQLite `results_as_hash` and the other settings of the `SQLite3::Database` are kept too.
* **Forked processes** (Puma / Sidekiq / Resque workers, `Process.fork`): connections opened before the fork stay the
  parent's. connection_pool's fork handling replaces the pooled ones in the child without closing the parent's
  sessions, and the child lets go of every inherited connection the generated code has used (also ones another thread
  had checked out at fork time, and ones the child never uses), so its exit does not end them either.
  * A `pg` connection used directly (not from a `ConnectionPool`) reconnects in the child; a `mysql2` client used that
    way raises `Mysql2::Error::ConnectionError` in the child (open clients in the process that uses them).
  * SQLite: the sqlite3 gem closes writable databases a child inherits, so open the database again in the child.
  * macOS: connecting from a forked child can crash in libpq's GSSAPI probe; set `gssencmode: 'disable'` (or
    `PGGSSENCMODE=disable`), as usual for forking `pg` apps there.

## Async / fibers

The generated code is plain synchronous Ruby and works with the Fiber scheduler
([`async`](https://github.com/socketry/async)): inside `Sync { ... }`, pooled `pg` and `mysql2` queries run
concurrently (`mysql2` blocks the thread on Windows). MySQL parameters are quoted client-side with
`Mysql2::Client#escape` and sent with `Client#query`, not server-side prepared statements. SQLite queries run one at a
time.
