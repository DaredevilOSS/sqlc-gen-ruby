-- Same file and query name as pg_queries/first.sql, different SQL: prepared statements must not be shared.
-- name: GetPgOptionAuthor :one
SELECT id, 'second module' AS label
FROM options_audit.option_items
WHERE id = sqlc.arg(id);
