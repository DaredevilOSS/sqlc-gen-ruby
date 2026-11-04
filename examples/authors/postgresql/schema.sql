CREATE TABLE authors (
    id   BIGSERIAL PRIMARY KEY,
    name text      NOT NULL,
    bio  text
);

CREATE TABLE books (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    author_id BIGINT NOT NULL,
    description TEXT,
    FOREIGN KEY (author_id) REFERENCES authors (id) ON DELETE CASCADE
);

CREATE TABLE deferred_books (
    id BIGSERIAL PRIMARY KEY,
    author_id BIGINT NOT NULL REFERENCES authors (id) DEFERRABLE INITIALLY DEFERRED
);

CREATE SCHEMA extended;

CREATE EXTENSION IF NOT EXISTS hstore;
CREATE EXTENSION IF NOT EXISTS ltree;

CREATE TYPE extended.bio_type AS ENUM ('Autobiography', 'Biography', 'Memoir');

CREATE TABLE extended.bios (
    author_name VARCHAR(100),
    name VARCHAR(100),
    bio_type extended.bio_type,
    PRIMARY KEY (author_name, name)
);

CREATE TYPE extended.dimensions AS (width INTEGER, height INTEGER);

CREATE DOMAIN positive_int AS INTEGER CHECK (VALUE > 0);

-- Type coverage: one table per type family, written by one Insert and read by one Get query.

CREATE TABLE postgres_numeric_types (
    c_boolean BOOLEAN,
    c_smallint SMALLINT,
    c_integer INTEGER,
    c_bigint BIGINT,
    c_serial SERIAL,
    c_decimal DECIMAL(2,1),
    c_numeric NUMERIC(100, 50),
    c_real REAL,
    c_double_precision DOUBLE PRECISION,
    c_money MONEY,
    c_oid OID,
    c_positive positive_int
);

CREATE TABLE postgres_string_types (
    c_char CHAR,
    c_varchar VARCHAR(10),
    c_text TEXT,
    c_not_null TEXT NOT NULL DEFAULT 'x',
    c_xml XML,
    c_tsvector TSVECTOR,
    c_ltree LTREE,
    c_hstore HSTORE,
    c_regclass REGCLASS
);

CREATE TABLE postgres_datetime_types (
    c_date DATE,
    c_time TIME,
    c_timetz TIMETZ,
    c_timestamp TIMESTAMP,
    c_timestamptz TIMESTAMP WITH TIME ZONE,
    c_interval INTERVAL
);

CREATE TABLE postgres_json_types (
    id INTEGER PRIMARY KEY,
    c_json JSON,
    c_jsonb JSONB
);

CREATE TABLE postgres_array_types (
    id BIGINT PRIMARY KEY,
    -- scalars that :copyfrom / :batchexec encode next to the arrays
    c_boolean BOOLEAN,
    c_double_precision DOUBLE PRECISION,
    c_text_array TEXT [],
    c_integer_array INTEGER [],
    c_uuid_array UUID [],
    c_bio_type_array extended.bio_type [],
    c_bytea_array BYTEA [],
    c_jsonb_array JSONB [],
    c_numeric_array NUMERIC [],
    c_timestamptz_array TIMESTAMPTZ [],
    c_integer_matrix INTEGER [][],
    c_text_matrix TEXT [][]
);

CREATE TABLE postgres_special_types (
    c_bytea BYTEA,
    c_bit BIT(1),
    c_varbit VARBIT,
    c_uuid UUID,
    c_inet INET,
    c_cidr CIDR,
    c_macaddr MACADDR,
    c_point POINT,
    c_int4range INT4RANGE,
    c_dimensions extended.dimensions
);

COMMENT ON TABLE authors IS 'People who wrote at least one book.';
COMMENT ON COLUMN authors.bio IS 'Short biography, NULL when unknown.';
COMMENT ON TYPE extended.bio_type IS 'Kinds of biographies.';

-- enum values that are Ruby keywords or the enum module's own ALL constant
CREATE TYPE step AS ENUM ('begin', 'end', 'all', 'BEGIN', 'nil', 'self', '__FILE__');

CREATE TABLE regressions (
  id        bigint PRIMARY KEY,
  "order"   text NOT NULL,
  payload   bytea,
  doc       jsonb,
  bio_types extended.bio_type[],
  uids      uuid[],
  step      step
);

CREATE TABLE "MixedCaseCopies" ("Id" BIGINT NOT NULL PRIMARY KEY, "SomeValue" TEXT);

CREATE TABLE name_cases (
    id BIGINT PRIMARY KEY,
    "class" TEXT NOT NULL,
    "end" TEXT NOT NULL,
    "hash" TEXT NOT NULL,
    "method" TEXT NOT NULL,
    "count" INTEGER NOT NULL,
    "camelCase" TEXT NOT NULL,
    "HTTPServer" TEXT NOT NULL,
    "initialize" TEXT NOT NULL
);

-- Tables whose models share their name with a Ruby core or library constant used by the generated code
-- (PgCodegen::Exception, ...): generated code refers to those constants as ::Exception, ::Thread, ...
CREATE TABLE exceptions (id BIGSERIAL PRIMARY KEY);
CREATE TABLE standard_errors (id BIGSERIAL PRIMARY KEY);
CREATE TABLE threads (id BIGSERIAL PRIMARY KEY);
CREATE TABLE processes (id BIGSERIAL PRIMARY KEY);
CREATE TABLE data (id BIGSERIAL PRIMARY KEY);
CREATE TABLE structs (id BIGSERIAL PRIMARY KEY);
CREATE TABLE sets (id BIGSERIAL PRIMARY KEY);
CREATE TABLE strings (id BIGSERIAL PRIMARY KEY);
CREATE TABLE integers (id BIGSERIAL PRIMARY KEY);
CREATE TABLE times (id BIGSERIAL PRIMARY KEY);
CREATE TABLE encodings (id BIGSERIAL PRIMARY KEY);
CREATE TABLE monitors (id BIGSERIAL PRIMARY KEY);
CREATE TABLE mutexes (id BIGSERIAL PRIMARY KEY);
CREATE TABLE connection_pools (id BIGSERIAL PRIMARY KEY);

-- Dropped and recreated by the E2E tests while connections are open (a migration run with the application up).
CREATE SCHEMA late;
CREATE TYPE late.mood AS ENUM ('calm', 'happy');
CREATE TABLE late.feelings (id INTEGER PRIMARY KEY, moods late.mood[] NOT NULL);
