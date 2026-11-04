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

-- name: InsertMysqlNumericTypes :exec
INSERT INTO mysql_numeric_types (
  id, c_bool, c_boolean, c_tinyint, c_smallint, c_mediumint, c_int, c_integer, c_bigint, c_bigint_unsigned, c_decimal, c_dec, c_numeric, c_fixed, c_decimal_wide, c_float, c_double, c_double_precision
) VALUES (
  ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?
);

-- name: GetMysqlNumericTypes :one
SELECT * FROM mysql_numeric_types WHERE id = ?;

-- name: InsertMysqlStringTypes :exec
INSERT INTO mysql_string_types (
  id, c_char, c_nchar, c_national_char, c_varchar, c_tinytext, c_text, c_mediumtext, c_longtext, c_json
) VALUES (
  ?, ?, ?, ?, ?, ?, ?, ?, ?, ?
);

-- name: GetMysqlStringTypes :one
SELECT * FROM mysql_string_types WHERE id = ?;

-- name: InsertMysqlDatetimeTypes :exec
INSERT INTO mysql_datetime_types (
  id, c_date, c_time, c_datetime, c_datetime_6, c_timestamp, c_year
) VALUES (
  ?, ?, ?, ?, ?, ?, ?
);

-- name: GetMysqlDatetimeTypes :one
SELECT * FROM mysql_datetime_types WHERE id = ?;

-- name: CopyMysqlDatetimeTypes :copyfrom
INSERT INTO mysql_datetime_types (id, c_datetime_6) VALUES (?, ?);

-- name: InsertMysqlBinaryTypes :exec
INSERT INTO mysql_binary_types (
  id, c_bit, c_bit_16, c_binary, c_varbinary, c_tinyblob, c_blob, c_mediumblob, c_longblob
) VALUES (
  ?, ?, ?, ?, ?, ?, ?, ?, ?
);

-- name: GetMysqlBinaryTypes :one
SELECT * FROM mysql_binary_types WHERE id = ?;

-- name: ListAuthorsPaged :many
SELECT * FROM authors
ORDER BY name
LIMIT ? OFFSET ?;

-- name: GetAuthorByNamePattern :many
SELECT * FROM authors
WHERE name LIKE COALESCE(sqlc.narg('name_pattern'), '%');

-- name: GetAuthorsByOptionalName :many
SELECT * FROM authors
WHERE (sqlc.narg(name_filter) IS NULL OR name = sqlc.narg(name_filter))
ORDER BY id
LIMIT ?;

-- name: PauseQuery :exec
SELECT SLEEP(sqlc.arg(seconds));

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

-- name: CopyRegressionRows :copyfrom
INSERT INTO regressions (id, `order`, note, payload) VALUES (?, ?, ?, ?);

-- name: SetRegressionStep :exec
UPDATE regressions SET step = ? WHERE id = ?;

-- name: GetRegressionStep :one
SELECT step FROM regressions WHERE id = ?;

-- name: ListRegressionRows :many
SELECT id, `order`, note, payload, code, doc, flags, amount FROM regressions ORDER BY id;

-- name: ListAuthorsWithOptionalBook :many
SELECT sqlc.embed(authors), sqlc.embed(books)
FROM authors
LEFT JOIN books ON authors.id = books.author_id
ORDER BY authors.id;

-- name: TruncateRegressions :exec
TRUNCATE TABLE regressions;

-- name: CopyRegressionTypes :copyfrom
INSERT INTO regressions (id, code, doc, flags, amount) VALUES (?, ?, ?, ?, ?);

-- name: CopyRegressionsIgnore :copyfrom
INSERT IGNORE INTO regressions (id, code) VALUES (?, ?);

-- name: CopyRegressionsReplace :copyfrom
REPLACE INTO regressions (id, code) VALUES (?, ?);

-- name: CreateRegressionsBatch :batchexec
INSERT INTO regressions (id, code, flags, amount) VALUES (?, ?, ?, ?);

-- name: CountRegressionsByCodes :batchone
SELECT count(*) AS matches FROM regressions WHERE code = ? OR code = ?;

-- name: FindAuthorsByExactName :many
SELECT id FROM authors WHERE name = sqlc.arg(name);

-- name: GetAuthorWithQuestionMarks :many
SELECT id FROM authors AS `?`
WHERE name = ? AND '?' = '?' AND "?" = "?" /* ? */
# ?
ORDER BY id;

-- name: InsertNameCase :exec
INSERT INTO name_cases (id, `class`, `end`, `hash`, `method`, `count`, `camelCase`, `HTTPServer`, `initialize`)
VALUES (sqlc.arg(id), sqlc.arg(class), sqlc.arg(end_), sqlc.arg(hash), sqlc.arg(method), sqlc.arg(count),
        sqlc.arg(camel_case), sqlc.arg(http_server), sqlc.arg(initialize));

-- name: GetNameCase :one
SELECT * FROM name_cases
WHERE id = sqlc.arg(id) AND `class` = sqlc.arg(class) AND `end` = sqlc.arg(end_) AND `hash` = sqlc.arg(hash)
  AND `method` = sqlc.arg(method) AND `count` = sqlc.arg(count)
  AND `HTTPServer` = sqlc.arg(http_server) AND `camelCase` = sqlc.arg(camel_case)
  AND `initialize` = sqlc.arg(initialize);

-- name: GetHTTPServer :one
SELECT * FROM name_cases WHERE id = sqlc.arg(id);

-- name: TruncateNameCases :exec
TRUNCATE TABLE name_cases;

-- name: CopyMixedCaseCopies :copyfrom
-- MySQL table names are case-sensitive on Linux: LOAD DATA must use `MixedCaseCopies`, not sqlc's lowercased name.
INSERT INTO `MixedCaseCopies` (`Id`, `SomeValue`) VALUES (?, ?);

-- name: CopyMixedCaseCopiesUnquoted :copyfrom
INSERT INTO MixedCaseCopies (SomeValue, Id) VALUES (?, ?);

-- name: ListMixedCaseCopies :many
SELECT * FROM `MixedCaseCopies` ORDER BY `Id`;

-- name: TruncateMixedCaseCopies :exec
TRUNCATE TABLE `MixedCaseCopies`;

-- name: GetUnnamedColumns :one
SELECT 1, 'two';

-- name: GetQuotedAlias :one
SELECT 1 AS `it's`;

-- name: GetAuthorsNotInIds :many
SELECT * FROM authors WHERE id NOT IN (sqlc.slice('ids')) ORDER BY id;

-- name: CreateException :exec
INSERT INTO exceptions (id) VALUES (NULL);

-- name: CountExceptions :one
SELECT COUNT(*) AS n FROM exceptions;

-- name: TruncateExceptions :exec
TRUNCATE TABLE exceptions;

-- name: HasAuthors :one
SELECT EXISTS (SELECT 1 FROM authors) AS has_any;
