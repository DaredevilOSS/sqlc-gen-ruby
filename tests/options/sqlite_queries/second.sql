-- name: GetOptionExtra :one
SELECT id, extra
FROM option_items
WHERE id = sqlc.arg(id);
