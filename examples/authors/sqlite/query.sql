-- name: GetAuthor :one
-- Returns the author with the given id, or nil when there is none.
SELECT * FROM authors
WHERE id = ? LIMIT 1;

-- name: ListAuthors :many
SELECT * FROM authors
ORDER BY name;

-- name: CreateAuthor :exec
INSERT INTO authors (
  name, bio
) VALUES (
  ?, ?
);

-- name: DeleteAuthor :exec
DELETE FROM authors
WHERE id = ?;

-- name: ListAuthorsPaged :many
SELECT * FROM authors
ORDER BY name
LIMIT sqlc.arg('limit') OFFSET sqlc.arg('offset');

-- name: GetAuthorByNamePattern :many
SELECT * FROM authors
WHERE name LIKE COALESCE(sqlc.narg('name_pattern'), '%');

-- name: CreateAuthorReturnId :execlastid
INSERT INTO authors (name, bio) VALUES (?, ?) RETURNING id;

-- name: UpdateAuthorBios :execrows
-- Sets the bio of every author that has one and returns how many were changed.
UPDATE authors
SET bio = ?
WHERE bio IS NOT NULL;

-- name: GetAuthorsByIds :many
SELECT * FROM authors WHERE id IN (sqlc.slice('ids'));

-- name: GetAuthorsByIdsAndNames :many
SELECT * FROM authors WHERE id IN (sqlc.slice('ids')) AND name IN (sqlc.slice('names'));

-- name: CopyAuthors :copyfrom
-- Bulk insert: pass an Array of CopyAuthorsArgs.
INSERT INTO authors (name, bio) VALUES (?, ?);

-- name: TruncateAuthors :exec
DELETE FROM authors;

-- name: CreateBook :execlastid
INSERT INTO books (name, author_id) VALUES (?, ?) RETURNING id;

-- name: ListAllAuthorsBooks :many
SELECT
    sqlc.embed(authors),
    sqlc.embed(books)
FROM authors INNER JOIN books ON authors.id = books.author_id
ORDER BY authors.name;

-- name: GetDuplicateAuthors :many
SELECT
    sqlc.embed(authors1),
    sqlc.embed(authors2)
FROM authors AS authors1
INNER JOIN authors AS authors2 ON authors1.name = authors2.name
WHERE authors1.id < authors2.id;

-- name: GetAuthorsByBookName :many
SELECT
    authors.*,
    sqlc.embed(books)
FROM authors INNER JOIN books ON authors.id = books.author_id
WHERE books.name = ?;

-- name: CreateAuthorResult :execresult
INSERT INTO authors (name, bio) VALUES (?, ?);

-- name: CreateAuthorsBatch :batchexec
INSERT INTO authors (name, bio) VALUES (?, ?);

-- name: GetAuthorBatch :batchone
SELECT * FROM authors WHERE id = ?;

-- name: ListAuthorsByNameBatch :batchmany
SELECT * FROM authors WHERE name = ? ORDER BY id;

-- name: InsertDeclaredTypes :exec
INSERT INTO declared_types (c_varchar, c_decimal, c_unsigned_big_int, c_native, c_double) VALUES (?, ?, ?, ?, ?);

-- name: GetDeclaredTypes :one
SELECT * FROM declared_types LIMIT 1;

-- name: TruncateDeclaredTypes :exec
DELETE FROM declared_types;

-- name: CreateRegression :exec
INSERT INTO regressions ("order", price) VALUES (?, ?) RETURNING id;

-- name: UpdateRegressionPrices :execrows
UPDATE regressions SET price = ? RETURNING id;

-- name: CopyRegressions :copyfrom
INSERT INTO regressions ("order", price) VALUES (?, ?);

-- name: ListRegressions :many
SELECT id, "order", price FROM regressions ORDER BY id;

-- name: GetMaxRegressionPrice :one
SELECT coalesce(max(price), 0) AS max_price FROM regressions;

-- name: TruncateRegressions :exec
DELETE FROM regressions;
