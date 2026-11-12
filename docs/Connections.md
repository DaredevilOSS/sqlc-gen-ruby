# Connections

A query object runs its queries on connections it takes from a pool. It is safe to create once and share between
threads.

## Getting a query object

**Let the plugin build the pool** (`pg`, `mysql2`). `connect` takes the driver's connection parameters and passes the
other options to [`connection_pool`](https://github.com/mperham/connection_pool):

```ruby
queries = PgCodegen::QuerySql.connect({ dbname: 'app', host: 'localhost' }, size: 5, timeout: 5)
queries = PgCodegen::QuerySql.connect(ENV.fetch('DATABASE_URL'), size: 5)          # pg also takes a URL
queries = Mysql2Codegen::QuerySql.connect({ database: 'app', host: 'localhost' }, size: 5)
```

**Bring your own pool.** Anything that responds to `#with` and yields a connection works, including a fake in tests:

```ruby
queries = PgCodegen::QuerySql.new(pool)
```

**SQLite** has no `connect`: pass a `SQLite3::Database`, opened with any options (`results_as_hash: true` included).

```ruby
queries = Sqlite3Codegen::QuerySql.new(SQLite3::Database.new('app.db'))
```

A `SQLite3::Database` is one connection, so threads and fibers sharing it take turns.

Both `connect` and `new` take `logger:`, see [Logging](Generated-Code.md#logging).

## Sharing a connection with another library

A connection that ActiveRecord (`raw_connection`), Sequel or your own code also uses keeps its settings. The generated
queries pass what they need with every call instead of changing the connection:

| Driver | Left untouched | What the generated queries use |
|---|---|---|
| `pg` | `type_map_for_results`, `type_map_for_queries`, `field_name_type` | their own type maps |
| `mysql2` | the client's query options and `Mysql2::Client.default_query_options` | `as: :array, cast: true, cast_booleans: false` |
| `sqlite3` | `results_as_hash` and the other settings of the `SQLite3::Database` | |

For a transaction the other library opened on the same connection, see
[Transactions](Transactions.md#inside-another-librarys-transaction).

## Forked processes

Puma, Sidekiq and Resque workers, and anything else that calls `Process.fork`, can inherit a query object:

* **Pooled connections:** connections opened before the fork stay the parent's. `connection_pool` replaces them in the
  child, and the child lets go of every inherited connection without closing the parent's session, also ones another
  thread had checked out at fork time and ones the child never uses. A child that exits does not end them either.
* **A `pg` connection used directly** (not from a `ConnectionPool`) reconnects in the child.
* **A `mysql2` client used directly** raises `Mysql2::Error::ConnectionError` in the child: open clients in the
  process that uses them.
* **SQLite:** the sqlite3 gem closes writable databases a child inherits, so open the database again in the child.
* **macOS:** connecting from a forked child can crash in libpq's GSSAPI probe. Set `gssencmode: 'disable'` (or
  `PGGSSENCMODE=disable`), as usual for forking `pg` applications there.

## Fibers and Async

The generated code is plain synchronous Ruby and works with the Fiber scheduler
([`async`](https://github.com/socketry/async)). Inside `Sync { ... }`:

| Driver | |
|---|---|
| `pg` | pooled queries run concurrently |
| `mysql2` | pooled queries run concurrently (on Windows `mysql2` blocks the thread) |
| `sqlite3` | queries run one at a time |

## Lost connections

A connection the server closed (restart, failover, killed backend) is reconnected (`pg`) or replaced in the pool
(`mysql2`) the next time it is checked out. The call that hit the dead connection still raises.

A `mysql2` client that mysql2 closed because a running query was interrupted (a stopped `Async` task, `Thread#raise`)
is replaced the same way, without failing the next call.

Inside a transaction a lost connection is never replaced silently: see
[Transactions](Transactions.md#lost-connections).

## Prepared statements

* **PostgreSQL** prepares each query once per connection. Behind pgbouncer in transaction mode, turn that off with
  [`preparedStatements: false`](Options.md#preparedstatements-pg).
* **MySQL** does not use server-side prepared statements: parameters are quoted client-side with
  `Mysql2::Client#escape` and sent with `Client#query`.
* **SQLite** prepares and closes a statement for each call.
