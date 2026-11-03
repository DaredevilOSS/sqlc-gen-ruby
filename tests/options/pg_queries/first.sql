-- name: GetPgOptionAuthor :one
SELECT id, note, tag, extra
FROM options_audit.option_items
WHERE id = sqlc.arg(id);
