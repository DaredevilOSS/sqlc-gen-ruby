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
    c_double DOUBLE PRECISION,
    c_json JSON,
    c_uuid UUID
);

CREATE TABLE regressions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    "order" VARCHAR(255) NOT NULL,
    price DECIMAL(10,2),
    payload BLOB
);

CREATE TABLE tags (
    name TEXT NOT NULL PRIMARY KEY,
    uses INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE name_cases (
  id INTEGER PRIMARY KEY,
  "class" TEXT NOT NULL,
  "end" TEXT NOT NULL,
  "hash" TEXT NOT NULL,
  "method" TEXT NOT NULL,
  "count" INTEGER NOT NULL,
  "camelCase" TEXT NOT NULL,
  "HTTPServer" TEXT NOT NULL
);

-- Tables whose models share their name with a Ruby core or library constant used by the generated code
-- (PgCodegen::Exception, ...): generated code refers to those constants as ::Exception, ::Thread, ...
CREATE TABLE exceptions (id INTEGER PRIMARY KEY);
CREATE TABLE standard_errors (id INTEGER PRIMARY KEY);
CREATE TABLE threads (id INTEGER PRIMARY KEY);
CREATE TABLE processes (id INTEGER PRIMARY KEY);
CREATE TABLE data (id INTEGER PRIMARY KEY);
CREATE TABLE structs (id INTEGER PRIMARY KEY);
CREATE TABLE sets (id INTEGER PRIMARY KEY);
CREATE TABLE strings (id INTEGER PRIMARY KEY);
CREATE TABLE integers (id INTEGER PRIMARY KEY);
CREATE TABLE times (id INTEGER PRIMARY KEY);
CREATE TABLE encodings (id INTEGER PRIMARY KEY);
CREATE TABLE monitors (id INTEGER PRIMARY KEY);
CREATE TABLE mutexes (id INTEGER PRIMARY KEY);
CREATE TABLE connection_pools (id INTEGER PRIMARY KEY);
