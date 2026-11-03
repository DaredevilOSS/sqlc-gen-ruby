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

-- name: GetAuthorsByOptionalName :many
SELECT * FROM authors
WHERE (sqlc.narg(name_filter) IS NULL OR name = sqlc.narg(name_filter))
ORDER BY id
LIMIT sqlc.arg(lim);

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

-- name: GetAuthorsByMixedPlaceholders :many
SELECT * FROM authors
WHERE name = sqlc.arg(n)
  AND id IN (sqlc.slice(ids))
  AND name = sqlc.arg(n)
  AND id > ?
  AND id IN (sqlc.slice(more))
  AND 'x?' != '?3'
ORDER BY id;

-- name: GetAuthorsByRepeatedNamedAndPositional :many
SELECT * FROM authors
WHERE name = sqlc.arg(n)
  AND name != sqlc.arg(other)
  AND id > ?
  AND name = sqlc.arg(n)
ORDER BY id;

-- name: GetAuthorsByRepeatedNamedAndPositionalBatch :batchone
SELECT * FROM authors
WHERE name = sqlc.arg(n)
  AND name != sqlc.arg(other)
  AND id > ?
  AND name = sqlc.arg(n)
ORDER BY id
LIMIT 1;

-- name: CopyAuthors :copyfrom
-- Bulk insert: pass an Array of CopyAuthorsArgs.
INSERT INTO authors (name, bio) VALUES (?, ?);

-- name: CopyAuthorsNamed :copyfrom
INSERT INTO authors (name, bio) VALUES (sqlc.arg(name), sqlc.arg(bio));

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
INSERT INTO declared_types (c_varchar, c_decimal, c_unsigned_big_int, c_native, c_double, c_json, c_uuid) VALUES (?, ?, ?, ?, ?, ?, ?);

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

-- name: CopyRegressionRows :copyfrom
INSERT INTO regressions (id, "order", price, payload) VALUES (?, ?, ?, ?);

-- name: ListRegressionRows :many
SELECT id, "order", price, payload FROM regressions ORDER BY id;

-- name: TruncateRegressionRows :exec
DELETE FROM regressions;

-- name: PauseQuery :exec
SELECT sleep(?);

-- name: CopyTagsOrReplace :copyfrom
INSERT OR REPLACE INTO tags (name, uses) VALUES (?, ?);

-- name: CopyTagsOrIgnore :copyfrom
INSERT OR IGNORE INTO tags (name, uses) VALUES (?, ?);

-- name: CopyTagsAddingUses :copyfrom
INSERT INTO tags (name, uses) VALUES (?, ?) ON CONFLICT (name) DO UPDATE SET uses = tags.uses + excluded.uses;

-- name: ListTags :many
SELECT name, uses FROM tags ORDER BY name;

-- name: TruncateTags :exec
DELETE FROM tags;

-- name: ListAuthorsWithOptionalBook :many
SELECT sqlc.embed(authors), sqlc.embed(books)
FROM authors
LEFT JOIN books ON authors.id = books.author_id
ORDER BY authors.id;

-- name: InsertNameCase :exec
INSERT INTO name_cases (id, "class", "end", "hash", "method", "count", "camelCase", "HTTPServer")
VALUES (sqlc.arg(id), sqlc.arg(class), sqlc.arg(end_), sqlc.arg(hash), sqlc.arg(method), sqlc.arg(count),
        sqlc.arg(camel_case), sqlc.arg(http_server));

-- name: GetNameCase :one
SELECT * FROM name_cases
WHERE id = sqlc.arg(id) AND "class" = sqlc.arg(class) AND "end" = sqlc.arg(end_) AND "hash" = sqlc.arg(hash)
  AND "method" = sqlc.arg(method) AND "count" = sqlc.arg(count)
  AND "HTTPServer" = sqlc.arg(http_server) AND "camelCase" = sqlc.arg(camel_case);

-- name: GetHTTPServer :one
SELECT * FROM name_cases WHERE id = sqlc.arg(id);

-- name: TruncateNameCases :exec
DELETE FROM name_cases;
