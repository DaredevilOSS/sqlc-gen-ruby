# Transactions

```ruby
queries.transaction(isolation: :serializable) do |tx|
  id = tx.create_author_return_id(name: 'a', bio: nil)
  tx.transaction { tx.create_book(name: 'b', author_id: id) }  # nested: a SAVEPOINT
  :done                                                         # the block's value is returned
end
```

## The basics

* Everything in the block runs on one connection.
* **Commit:** when the block ends, also with `break`, `return` or `throw`.
* **Rollback:** when the block raises or its thread is killed.
* **Nesting:** a `transaction` inside a transaction is a savepoint and rolls back only its own part.
* **Result:** `transaction` returns the value of the block.

### Isolation

| Driver | Keyword | Values |
|---|---|---|
| `pg`, `mysql2` | `isolation:` | `:read_uncommitted`, `:read_committed`, `:repeatable_read`, `:serializable` |
| `sqlite3` | `mode:` | `:deferred`, `:immediate`, `:exclusive` |

Any other value raises `ArgumentError` before anything runs. So does `isolation:` / `mode:` on a nested `transaction`,
because a savepoint cannot change them.

### Use `tx` inside the block

`tx` is a copy of the query object that is bound to the transaction:

* Its queries stay in the transaction from any fiber or thread (an `Enumerator`, an `Async` task, a `Thread`), one at
  a time.
* After the transaction is over it raises `TransactionEnded`.

The original `queries` object also joins the transaction when it is called from the thread that opened it (with
`connection_pool` or SQLite; a pool you inject must hand out the same connection again inside `#with`). From another
fiber or thread, `queries` and other query classes sharing the pool check out their own connection and run **outside**
the transaction, so pass `tx` there.

### Inside another library's transaction

When another library already opened a transaction on the same connection (`BEGIN`):

* **PostgreSQL, SQLite:** `transaction` is a savepoint in it.
* **MySQL** has no nested transactions, and its `BEGIN` commits the open transaction first. A later rollback no longer
  undoes the earlier work. Run the outer work in `transaction` too (inner calls then become savepoints), or finish
  the other transaction first.

## When something goes wrong

The rule behind everything below: a connection never goes back to the pool inside a transaction, and `transaction`
never reports a commit that did not happen.

### A statement fails and the block rescues the error

* **PostgreSQL** aborts the whole transaction when a statement fails, so `transaction` raises
  `PG::InFailedSqlTransaction` at the end instead of pretending it committed. To carry on after an error, run the
  statement in a nested `transaction`: only that savepoint is rolled back, and the outer block can rescue the error.
* **MySQL** rolls the whole transaction back on a deadlock (or a lock wait timeout with
  `innodb_rollback_on_timeout`), savepoints included. Every later query in the block and `transaction` itself then
  raise the error again: a `Mysql2::Error` with the same `error_number` and a message that starts with
  `transaction rolled back:`. Retry the whole `transaction`. A lock wait timeout without that setting fails only its
  statement, and the block can rescue it and go on.

### Interrupts

`Timeout`, `Thread#raise`, `Thread#kill` and a stopped `Async` task can arrive at any moment:

* **During `BEGIN`, `COMMIT` or `ROLLBACK`:** the interrupt waits for the statement to finish. A `BEGIN` / `COMMIT`
  that raises itself (a stopped `Async` task) is rolled back.
* **During a query on PostgreSQL** (inside or outside a transaction): the query is cancelled at once. The connection
  goes back to the pool idle, and a killed transaction rolls back without waiting for its query.
* **`Thread#kill` during a query on MySQL:** the client is closed, because mysql2 cannot send `ROLLBACK` while it
  waits for the query's result. The server rolls the transaction back and the pool replaces the client.

### Ruby below 3.3 with timeout < 0.4

The `timeout` gem bundled with Ruby before 3.3 leaves a block with `throw`, which cannot be told apart from your own
`break`, `return` or `throw`. With that gem all of them **roll back** instead of committing.

Use `gem 'timeout', '>= 0.4'` to keep those exits committing. A generated Gemfile (`generateGemfile: true`) for a
`rubyVersion` below 3.3 already has it.

With the old gem, a `Timeout` that interrupts a PostgreSQL query in a transaction still raises `Timeout::Error` (not
the `PG::InFailedSqlTransaction` of the cancelled query) after rolling back.

### Lost connections

A `pg` connection lost inside `transaction` is not reconnected. Every later call in the block and `transaction` itself
raise `PG::ConnectionBad`, so nothing after the loss runs outside the transaction; the server has rolled it back.

Outside a transaction, lost connections are replaced: see [Connections](Connections.md#lost-connections).

### SQLite

A SQLite transaction belongs to the thread that opened it and holds the database until it ends. Other threads and
fibers sharing the same `SQLite3::Database` wait for it.
