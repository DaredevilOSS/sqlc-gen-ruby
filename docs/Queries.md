# Queries

## Annotations

| Annotation | Returns | Notes |
|---|---|---|
| `:one` | the row or `nil` | plus a bang finder (`get_author!`) that raises `QuerySql::NotFound` instead of returning `nil` |
| `:many` | `Array` of rows | |
| `:exec` | `nil` | |
| `:execrows` | number of affected rows | MySQL: rows changed, not rows matched; connect with `flags: Mysql2::Client::FOUND_ROWS` to count matched rows |
| `:execlastid` | the new id | PostgreSQL / SQLite: needs `RETURNING id`; MySQL: the auto-increment id |
| `:execresult` | `ExecResult` (`rows_affected`, `last_insert_id`) | `last_insert_id` is `nil` on PostgreSQL (use `RETURNING`) |
| `:batchexec` / `:batchone` / `:batchmany` | `nil` / `Array` of rows or `nil` / `Array` of `Array`s of rows | take an `Array` of `<Query>Args` and run the query once per element, on one connection. Not atomic on their own: wrap them in `transaction` for all-or-nothing |
| `:copyfrom` | `nil` | bulk insert of an `Array` (or any `Enumerable`, also lazy) of `<Query>Args`; all rows or none |

### `:copyfrom`

| | Implementation |
|---|---|
| PostgreSQL | `COPY ... FROM STDIN` |
| MySQL | `LOAD DATA LOCAL INFILE`: needs `local_infile: true` in the `Mysql2::Client` params and `local_infile=1` on the server; duplicate keys and invalid values raise `Mysql2::Error` instead of being skipped |
| SQLite | batched multi-row `INSERT`s |

Conflict clauses are kept: `INSERT OR REPLACE` / `OR IGNORE` / `ON CONFLICT ... DO ...` on SQLite, `INSERT IGNORE`
(duplicates skipped) and `REPLACE` on MySQL. Clauses `COPY` / `LOAD DATA` cannot express (`ON CONFLICT` / `RETURNING`
on PostgreSQL, `ON DUPLICATE KEY UPDATE` on MySQL) are generation errors; use `:batchexec` for those.

* MySQL: `LOAD DATA` names the table and columns as the `INSERT` writes them (`` `MixedCase` ``): sqlc reports MySQL
  names in lowercase, but table names are case-sensitive on Linux.
* MySQL: `LOAD DATA` commits an open transaction that was started with raw SQL (`BEGIN`); call `:copyfrom` inside
  `transaction` instead.

## Macros

| Macro | PostgreSQL | MySQL | SQLite | Notes |
|---|:---:|:---:|:---:|---|
| `sqlc.arg` | ✅ | ✅ | ✅ | names a parameter (unnamed ones such as `ANY($1::BIGINT[])` become `param1`, ...) |
| `sqlc.narg` | ✅ | ✅ | ✅ | a nullable parameter (`T?`, defaults to `nil`) |
| `sqlc.slice` | 🚫 | ✅ | ✅ | `IN (sqlc.slice(ids))` takes an `Array` (an empty one: `IN` matches nothing, `NOT IN` everything). PostgreSQL: use `= ANY($1::bigint[])` with an array |
| `sqlc.embed` | ✅ | ✅ | ✅ | the row gets an attribute holding the table's model (`author`, `author2` for the same table twice); `nil` when an outer join found no row |

🚫 = not offered by sqlc for that database.

## Arguments

Keywords named after the parameters (`get_author(id:)`); `sqlc.arg(name)` names them yourself. Missing or unknown ones
raise `ArgumentError`. Nullable parameters named with `sqlc.arg` / `sqlc.narg` default to `nil`; other nullable
parameters (`VALUES ($1, $2)`) must be passed, even as `nil`.
