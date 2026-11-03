-- name: GetOptionAuthor :one
SELECT id, note, tag, extra
FROM option_items
WHERE id = sqlc.arg(id);

-- name: GetBothModels :one
SELECT sqlc.embed(author), sqlc.embed(authors)
FROM author
JOIN authors USING (id)
WHERE author.id = sqlc.arg(id);

-- name: ListOptionArticles :many
SELECT * FROM articles ORDER BY id;
