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

-- name: InsertPostgresNumericTypes :exec
INSERT INTO postgres_numeric_types (
  c_boolean, c_smallint, c_integer, c_bigint, c_decimal, c_numeric, c_real, c_double_precision, c_money, c_oid, c_positive
) VALUES (
  $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11
);

-- name: GetPostgresNumericTypes :one
SELECT * FROM postgres_numeric_types LIMIT 1;

-- name: InsertPostgresStringTypes :exec
INSERT INTO postgres_string_types (
  c_char, c_varchar, c_text, c_not_null, c_xml, c_tsvector, c_ltree, c_hstore, c_regclass
) VALUES (
  $1, $2, $3, $4, $5, $6, $7, $8, $9
);

-- name: GetPostgresStringTypes :one
SELECT * FROM postgres_string_types LIMIT 1;

-- name: InsertPostgresDatetimeTypes :exec
INSERT INTO postgres_datetime_types (
  c_date, c_time, c_timetz, c_timestamp, c_timestamptz, c_interval
) VALUES (
  $1, $2, $3, $4, $5, $6
);

-- name: GetPostgresDatetimeTypes :one
SELECT * FROM postgres_datetime_types LIMIT 1;

-- name: InsertPostgresJSONTypes :exec
INSERT INTO postgres_json_types (id, c_json, c_jsonb) VALUES ($1, $2, $3);

-- name: GetPostgresJSONTypes :one
SELECT c_json, c_jsonb FROM postgres_json_types WHERE id = $1;

-- name: TogglePostgresJSONBType :exec
UPDATE postgres_json_types
SET c_jsonb = to_jsonb(NOT (c_jsonb #>> '{}')::boolean)
WHERE id = $1;

-- name: InsertPostgresArrayTypes :exec
INSERT INTO postgres_array_types (
  id, c_boolean, c_double_precision, c_text_array, c_integer_array, c_uuid_array, c_bio_type_array, c_bytea_array, c_jsonb_array, c_numeric_array, c_timestamptz_array, c_integer_matrix, c_text_matrix
) VALUES (
  $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13
);

-- name: ListPostgresArrayTypes :many
SELECT * FROM postgres_array_types ORDER BY id;

-- name: InsertPostgresArrayTypesBatch :batchexec
INSERT INTO postgres_array_types (id, c_boolean, c_double_precision, c_bytea_array, c_jsonb_array, c_integer_array, c_numeric_array, c_timestamptz_array) VALUES ($1, $2, $3, $4, $5, $6, $7, $8);

-- name: CopyPostgresArrayTypes :copyfrom
INSERT INTO postgres_array_types (id, c_boolean, c_double_precision, c_bytea_array, c_jsonb_array, c_integer_array, c_numeric_array, c_timestamptz_array) VALUES ($1, $2, $3, $4, $5, $6, $7, $8);

-- name: CountPostgresArrayTypesAbove :one
SELECT count(*) FROM postgres_array_types WHERE id > sqlc.arg(MIN_ID);

-- name: InsertPostgresSpecialTypes :exec
INSERT INTO postgres_special_types (
  c_bytea, c_bit, c_varbit, c_uuid, c_inet, c_cidr, c_macaddr, c_point, c_int4range, c_dimensions
) VALUES (
  $1, $2, $3, $4, $5, $6, $7, $8, $9, $10
);

-- name: GetPostgresSpecialTypes :one
SELECT * FROM postgres_special_types LIMIT 1;

-- name: TruncateTestTables :exec
TRUNCATE TABLE
  postgres_numeric_types, postgres_string_types, postgres_datetime_types, postgres_json_types, postgres_array_types,
  postgres_special_types, extended.bios, regressions, name_cases, "MixedCaseCopies", deferred_books;

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

-- name: SetRegressionStep :one
UPDATE regressions SET step = $2 WHERE id = $1 RETURNING step;

-- name: InsertNameCase :exec
INSERT INTO name_cases (id, "class", "end", "hash", "method", "count", "camelCase", "HTTPServer", "initialize")
VALUES (sqlc.arg(id), sqlc.arg(class), sqlc.arg(end_), sqlc.arg(hash), sqlc.arg(method), sqlc.arg(count),
        sqlc.arg(camel_case), sqlc.arg(http_server), sqlc.arg(initialize));

-- name: GetNameCase :one
SELECT * FROM name_cases
WHERE id = sqlc.arg(id) AND "class" = sqlc.arg(class) AND "end" = sqlc.arg(end_) AND "hash" = sqlc.arg(hash)
  AND "method" = sqlc.arg(method) AND "count" = sqlc.arg(count)
  AND "HTTPServer" = sqlc.arg(http_server) AND "camelCase" = sqlc.arg(camel_case)
  AND "initialize" = sqlc.arg(initialize);

-- name: GetHTTPServer :one
SELECT * FROM name_cases WHERE id = sqlc.arg(id);

-- name: CopyMixedCaseCopies :copyfrom
INSERT INTO "MixedCaseCopies" ("Id", "SomeValue") VALUES ($1, $2);

-- name: ListMixedCaseCopies :many
SELECT * FROM "MixedCaseCopies" ORDER BY "Id";

-- name: GetUnnamedColumns :one
SELECT 1, 'two';

-- name: GetQuotedAlias :one
SELECT 1 AS "it's";

-- name: CreateException :exec
INSERT INTO exceptions DEFAULT VALUES;

-- name: CountExceptions :one
SELECT COUNT(*) AS n FROM exceptions;

-- name: TruncateExceptions :exec
TRUNCATE exceptions;

-- name: CreateLateFeeling :exec
INSERT INTO late.feelings (id, moods) VALUES ($1, $2);

-- name: GetLateFeeling :one
SELECT moods FROM late.feelings WHERE id = $1;

-- name: HasAuthors :one
SELECT EXISTS (SELECT 1 FROM authors) AS has_any;
