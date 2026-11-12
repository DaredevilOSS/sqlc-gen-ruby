# Queries

Each query in your `.sql` files becomes one method. Its annotation (`-- name: GetAuthor :one`) decides what the
method returns.

## Annotations

| Annotation | Returns | Notes |
|---|---|---|
| `:one` | the row or `nil` | also generates `get_author!`, which raises `QuerySql::NotFound` instead of returning `nil` |
| `:many` | `Array` of rows | |
| `:exec` | `nil` | |
| `:execrows` | number of affected rows | MySQL counts rows changed, not rows matched; connect with `flags: Mysql2::Client::FOUND_ROWS` to count matched rows |
| `:execlastid` | the new id | PostgreSQL / SQLite: the query needs `RETURNING id`. MySQL: the auto-increment id |
| `:execresult` | `ExecResult` (`rows_affected`, `last_insert_id`) | `last_insert_id` is `nil` on PostgreSQL; use `RETURNING` there |
| `:batchexec` | `nil` | see [Batches](#batches) |
| `:batchone` | `Array` of rows or `nil` | |
| `:batchmany` | `Array` of `Array`s of rows | |
| `:copyfrom` | `nil` | see [`:copyfrom`](#copyfrom) |

## Arguments

```ruby
queries.get_author(id: 1)
queries.create_author(name: 'Seuss', bio: nil)
```

* Arguments are keywords named after the parameters. Name one yourself with `sqlc.arg(name)`; a parameter sqlc cannot
  name (`ANY($1::BIGINT[])`) becomes `param1`, `param2`, ...
* Missing or unknown keywords raise `ArgumentError`.
* A nullable parameter named with `sqlc.arg` / `sqlc.narg` is optional and defaults to `nil`. Other nullable
  parameters (`VALUES ($1, $2)`) must be passed, even as `nil`.

## Macros

| Macro | PostgreSQL | MySQL | SQLite | What it does |
|---|:---:|:---:|:---:|---|
| `sqlc.arg(name)` | ✅ | ✅ | ✅ | names a parameter |
| `sqlc.narg(name)` | ✅ | ✅ | ✅ | names a nullable parameter (`T?`, defaults to `nil`) |
| `sqlc.slice(ids)` | 🚫 | ✅ | ✅ | `IN (sqlc.slice(ids))` takes an `Array`. With an empty one, `IN` matches nothing and `NOT IN` everything |
| `sqlc.embed(table)` | ✅ | ✅ | ✅ | the row gets an attribute holding the table's model (`author`; `author2` when the table is embedded twice). It is `nil` when an outer join found no row |

🚫 sqlc does not offer `sqlc.slice` for PostgreSQL. Use an array parameter instead: `WHERE id = ANY($1::bigint[])`.

Two result columns with the same name (`a.id, b.id`) are a generation error: alias one (`b.id AS book_id`) or use
`sqlc.embed`.

## Batches

`:batchexec`, `:batchone` and `:batchmany` take an `Array` of `<Query>Args` and run the query once per element, on one
connection:

```ruby
queries.create_authors_batch([
  PgCodegen::CreateAuthorsBatchArgs.new(name: 'a', bio: nil),
  PgCodegen::CreateAuthorsBatchArgs.new(name: 'b', bio: nil)
])
```

A batch is not atomic on its own: wrap it in [`transaction`](Transactions.md) for all-or-nothing.

## `:copyfrom`

A bulk insert of an `Array`, or any `Enumerable` (also a lazy one), of `<Query>Args`. Either all rows are inserted or
none.

| Database | Implementation | Requirements |
|---|---|---|
| PostgreSQL | `COPY ... FROM STDIN` | |
| MySQL | `LOAD DATA LOCAL INFILE` | `local_infile: true` in the `Mysql2::Client` params and `local_infile=1` on the server |
| SQLite | batched multi-row `INSERT`s | |

**Conflict clauses**

| Database | Kept | Generation error (use `:batchexec` instead) |
|---|---|---|
| PostgreSQL | | `ON CONFLICT`, `RETURNING` |
| MySQL | `INSERT IGNORE` (duplicates are skipped), `REPLACE` | `ON DUPLICATE KEY UPDATE` |
| SQLite | `INSERT OR REPLACE`, `INSERT OR IGNORE`, `ON CONFLICT ... DO ...` | |

**MySQL notes**

* Without `INSERT IGNORE`, duplicate keys and invalid values raise `Mysql2::Error` instead of being skipped or coerced
  as `LOAD DATA` would do by itself.
* `LOAD DATA` commits a transaction that was opened with raw SQL (`BEGIN`). Call `:copyfrom` inside
  [`transaction`](Transactions.md) instead.
* Table and column names are written as in your `INSERT` (`` `MixedCase` ``), so mixed-case tables work on Linux, where
  MySQL table names are case-sensitive.
