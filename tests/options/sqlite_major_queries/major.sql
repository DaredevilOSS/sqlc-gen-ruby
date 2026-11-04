-- name: CreateMajorArticle :exec
INSERT INTO articles (title) VALUES (sqlc.arg(title));

-- name: CountMajorArticles :one
SELECT COUNT(*) AS total FROM articles;
