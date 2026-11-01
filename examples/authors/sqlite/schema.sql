CREATE TABLE authors (
  id   INTEGER PRIMARY KEY AUTOINCREMENT,
  name text      NOT NULL,
  bio  text
);


CREATE TABLE books (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    author_id INTEGER NOT NULL,
    description TEXT,
    FOREIGN KEY (author_id) REFERENCES authors (id) ON DELETE CASCADE
);
