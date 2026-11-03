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

-- name: UpdateAuthor :exec
UPDATE authors 
SET bio = ?
WHERE id = ?;

-- name: CreateAuthorReturnId :execlastid
INSERT INTO authors (
    name, bio
) VALUES (
    ?, ?
);

-- name: DeleteAuthor :exec
DELETE FROM authors
WHERE id = ?;

-- name: Test :one
SELECT * FROM node_mysql_types
LIMIT 1;

-- name: ListAuthorsPaged :many
SELECT * FROM authors
ORDER BY name
LIMIT ? OFFSET ?;

-- name: GetAuthorByNamePattern :many
SELECT * FROM authors
WHERE name LIKE COALESCE(sqlc.narg('name_pattern'), '%');

-- name: UpdateAuthorBios :execrows
-- Sets the bio of every author that has one and returns how many were changed.
UPDATE authors
SET bio = sqlc.arg('bio')
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
INSERT INTO books (name, author_id) VALUES (?, ?);

-- name: ListAllAuthorsBooks :many
SELECT sqlc.embed(authors), sqlc.embed(books)
FROM authors JOIN books ON authors.id = books.author_id
ORDER BY authors.name;

-- name: GetDuplicateAuthors :many
SELECT sqlc.embed(authors1), sqlc.embed(authors2)
FROM authors authors1 JOIN authors authors2 ON authors1.name = authors2.name
WHERE authors1.id < authors2.id;

-- name: GetAuthorsByBookName :many
SELECT authors.*, sqlc.embed(books)
FROM authors JOIN books ON authors.id = books.author_id
WHERE books.name = ?;

-- name: CreateExtendedBio :exec
INSERT INTO extended_bios (author_name, name, bio_type, author_type) VALUES (?, ?, ?, ?);

-- name: GetFirstExtendedBioByType :one
SELECT * FROM extended_bios WHERE bio_type = ? LIMIT 1;

-- name: TruncateExtendedBios :exec
DELETE FROM extended_bios;

-- name: CreateAuthorResult :execresult
INSERT INTO authors (name, bio) VALUES (?, ?);

-- name: CreateAuthorsBatch :batchexec
INSERT INTO authors (name, bio) VALUES (?, ?);

-- name: GetAuthorBatch :batchone
SELECT * FROM authors WHERE id = ?;

-- name: ListAuthorsByNameBatch :batchmany
SELECT * FROM authors WHERE name = ? ORDER BY id;

-- name: CountRegressionsByText :one
SELECT count(*) FROM regressions WHERE `order` = sqlc.arg(term) OR note = sqlc.arg(term);

-- name: ListRegressionsByIds :many
SELECT id, `order`, note FROM regressions WHERE id IN (?, ?, ?) ORDER BY id;

-- name: CopyRegressions :copyfrom
INSERT INTO regressions (`order`, note) VALUES (?, ?);

-- name: TruncateRegressions :exec
TRUNCATE TABLE regressions;
