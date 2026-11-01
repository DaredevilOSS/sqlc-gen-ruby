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

CREATE TABLE declared_types (
    c_varchar VARCHAR(255),
    c_decimal DECIMAL(10, 5),
    c_unsigned_big_int UNSIGNED BIG INT,
    c_native NATIVE CHARACTER(70),
    c_double DOUBLE PRECISION
);
