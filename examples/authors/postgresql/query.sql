-- name: GetAuthor :one
-- Returns the author with the given id, or nil when there is none.
SELECT * FROM authors
WHERE id = $1 LIMIT 1;

-- name: ListAuthors :many
SELECT * FROM authors
ORDER BY name;

-- name: CreateAuthor :one
INSERT INTO authors (
    name, bio
) VALUES (
    $1, $2
)
RETURNING *;

-- name: DeleteAuthor :exec
DELETE FROM authors
WHERE id = $1;

-- name: Test :one
SELECT * FROM node_postgres_types
LIMIT 1;

-- name: SetJSONRoundTrip :exec
INSERT INTO json_round_trips (id, json_value, jsonb_value) VALUES ($1, $2, $3);

-- name: GetJSONRoundTrip :one
SELECT json_value, jsonb_value FROM json_round_trips WHERE id = $1;

-- name: ToggleJSONBRoundTrip :exec
UPDATE json_round_trips
SET jsonb_value = to_jsonb(NOT (jsonb_value #>> '{}')::boolean)
WHERE id = $1;

-- name: TruncateJSONRoundTrips :exec
TRUNCATE TABLE json_round_trips;

-- name: PauseQuery :exec
SELECT pg_sleep(sqlc.arg(seconds)::double precision);

-- name: ListAuthorsPaged :many
SELECT * FROM authors
ORDER BY name
LIMIT sqlc.arg('limit')
OFFSET sqlc.arg('offset');

-- name: GetAuthorByNamePattern :many
SELECT * FROM authors
WHERE name LIKE COALESCE(sqlc.narg('name_pattern'), '%');

-- name: GetAuthorsByOptionalName :many
SELECT * FROM authors
WHERE (sqlc.narg(name_filter)::text IS NULL OR name = sqlc.narg(name_filter)::text)
ORDER BY id
LIMIT sqlc.arg(lim);

-- name: CreateAuthorReturnId :execlastid
INSERT INTO authors (name, bio) VALUES ($1, $2) RETURNING id;

-- name: UpdateAuthorBios :execrows
-- Sets the bio of every author that has one and returns how many were changed.
UPDATE authors
SET bio = $1
WHERE bio IS NOT NULL;

-- name: GetAuthorsByIds :many
SELECT * FROM authors
WHERE id = ANY($1::BIGINT []);

-- name: GetAuthorsByIdsAndNames :many
SELECT * FROM authors
WHERE id = ANY($1::BIGINT []) AND name = ANY($2::TEXT []);

-- name: CopyAuthors :copyfrom
-- Bulk insert: pass an Array of CopyAuthorsArgs.
INSERT INTO authors (name, bio) VALUES ($1, $2);

-- name: TruncateAuthors :exec
TRUNCATE TABLE authors CASCADE;

-- name: CreateBook :execlastid
INSERT INTO books (name, author_id) VALUES ($1, $2) RETURNING id;

-- name: CreateDeferredBook :exec
INSERT INTO deferred_books (author_id) VALUES ($1);

-- name: TruncateDeferredBooks :exec
TRUNCATE TABLE deferred_books;

-- name: ListAllAuthorsBooks :many
SELECT
    sqlc.embed(authors),
    sqlc.embed(books)
FROM authors
INNER JOIN books ON authors.id = books.author_id
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
WHERE books.name = $1;

-- name: CreateExtendedBio :exec
INSERT INTO extended.bios (author_name, name, bio_type) VALUES ($1, $2, $3);

-- name: GetFirstExtendedBioByType :one
SELECT * FROM extended.bios WHERE bio_type = $1 LIMIT 1;

-- name: TruncateExtendedBios :exec
TRUNCATE TABLE extended.bios;

-- name: InsertExtraTypes :exec
INSERT INTO postgres_extra_types (c_uuid, c_jsonb, c_text_array, c_integer_array, c_timestamptz, c_inet, c_money, c_not_null)
VALUES ($1, $2, $3, $4, $5, $6, $7, $8);

-- name: GetExtraTypes :one
SELECT * FROM postgres_extra_types LIMIT 1;

-- name: TruncateExtraTypes :exec
TRUNCATE TABLE postgres_extra_types;

-- name: InsertRemainingTypes :exec
INSERT INTO postgres_remaining_types (
  c_hstore, c_ltree, c_regclass, c_cidr, c_macaddr, c_interval, c_varbit, c_xml,
  c_numeric, c_bigint, c_timestamp, c_timestamptz, c_text_matrix
) VALUES (
  $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13
);

-- name: GetRemainingTypes :one
SELECT * FROM postgres_remaining_types LIMIT 1;

-- name: TruncateRemainingTypes :exec
TRUNCATE TABLE postgres_remaining_types;

-- name: InsertArrayTypes :exec
INSERT INTO postgres_array_types (c_uuid_array, c_bio_type_array, c_integer_matrix) VALUES ($1, $2, $3);

-- name: GetArrayTypes :one
SELECT * FROM postgres_array_types LIMIT 1;

-- name: TruncateArrayTypes :exec
TRUNCATE TABLE postgres_array_types;

-- name: ListAuthorsWithOptionalBook :many
SELECT
    sqlc.embed(authors),
    sqlc.embed(books)
FROM authors
LEFT JOIN books ON authors.id = books.author_id
ORDER BY authors.name;

-- name: ListAuthorsBetweenIds :many
SELECT * FROM authors
WHERE id > $1 AND id < $2
ORDER BY id;

-- name: InsertSpecialTypes :exec
INSERT INTO postgres_special_types (c_timetz, c_tsvector, c_point, c_int4range, c_oid, c_dimensions, c_positive)
VALUES ($1, $2, $3, $4, $5, $6, $7);

-- name: GetSpecialTypes :one
SELECT * FROM postgres_special_types LIMIT 1;

-- name: TruncateSpecialTypes :exec
TRUNCATE TABLE postgres_special_types;

-- name: CreateAuthorResult :execresult
INSERT INTO authors (name, bio) VALUES ($1, $2);

-- name: CreateAuthorsBatch :batchexec
INSERT INTO authors (name, bio) VALUES ($1, $2);

-- name: GetAuthorBatch :batchone
SELECT * FROM authors WHERE id = $1;

-- name: ListAuthorsByNameBatch :batchmany
SELECT * FROM authors WHERE name = $1 ORDER BY id;

-- name: CreateRegression :one
INSERT INTO regressions (id, "order", payload, doc, bio_types, uids) VALUES ($1, $2, $3, $4, $5, $6) RETURNING *;

-- name: CreateRegressionIfNew :execlastid
INSERT INTO regressions (id, "order") VALUES ($1, $2) ON CONFLICT (id) DO NOTHING RETURNING id;

-- name: CopyRegressions :copyfrom
INSERT INTO regressions (id, "order", payload, doc) VALUES ($1, $2, $3, $4);

-- name: CreateRegressionsBatch :batchexec
INSERT INTO regressions (id, "order", payload, doc) VALUES ($1, $2, $3, $4);

-- name: ListRegressions :many
SELECT * FROM regressions WHERE (sqlc.narg(order_name)::text IS NULL OR "order" = sqlc.narg(order_name)) ORDER BY id;

-- name: TruncateRegressions :exec
TRUNCATE TABLE regressions;

-- name: CreateBatchTypesBatch :batchexec
INSERT INTO batch_types (id, ok, ratio, blobs, docs, counts, amounts, stamps) VALUES ($1, $2, $3, $4, $5, $6, $7, $8);

-- name: CopyBatchTypes :copyfrom
INSERT INTO batch_types (id, ok, ratio, blobs, docs, counts, amounts, stamps) VALUES ($1, $2, $3, $4, $5, $6, $7, $8);

-- name: ListBatchTypes :many
SELECT * FROM batch_types ORDER BY id;

-- name: CountBatchTypesAbove :one
SELECT count(*) FROM batch_types WHERE id > sqlc.arg(MIN_ID);

-- name: TruncateBatchTypes :exec
TRUNCATE TABLE batch_types;

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
TRUNCATE TABLE name_cases;
