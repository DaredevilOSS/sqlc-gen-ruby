CREATE TABLE authors (
    id   BIGSERIAL PRIMARY KEY,
    name text      NOT NULL,
    bio  text
);

CREATE TABLE node_postgres_types (
    c_bit BIT(1),
    c_smallint SMALLINT,
    c_boolean BOOLEAN,
    c_integer INTEGER,
    c_bigint BIGINT,
    c_serial SERIAL,
    c_decimal DECIMAL(2,1),
    c_numeric NUMERIC(2,1),
    c_real REAL,
    c_double_precision DOUBLE PRECISION,
    
    /* Date and Time Data Types */
    c_date DATE,
    c_time TIME,
    c_timestamp TIMESTAMP,
    
    /* String Data Type Syntax */
    c_char CHAR,
    c_varchar VARCHAR(10),
    c_bytea BYTEA,
    c_text TEXT,
    c_json JSON
);

CREATE TABLE books (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    author_id BIGINT NOT NULL,
    description TEXT,
    FOREIGN KEY (author_id) REFERENCES authors (id) ON DELETE CASCADE
);

CREATE SCHEMA extended;

CREATE TYPE extended.bio_type AS ENUM ('Autobiography', 'Biography', 'Memoir');

CREATE TABLE extended.bios (
    author_name VARCHAR(100),
    name VARCHAR(100),
    bio_type extended.bio_type,
    PRIMARY KEY (author_name, name)
);

CREATE TABLE postgres_extra_types (
    c_uuid UUID,
    c_jsonb JSONB,
    c_text_array TEXT [],
    c_integer_array INTEGER [],
    c_timestamptz TIMESTAMP WITH TIME ZONE,
    c_inet INET,
    c_money MONEY,
    c_not_null TEXT NOT NULL DEFAULT 'x'
);
