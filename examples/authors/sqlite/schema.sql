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

CREATE TABLE regressions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    "order" VARCHAR(255) NOT NULL,
    price DECIMAL(10,2)
);
