DROP SCHEMA IF EXISTS options_audit CASCADE;
CREATE SCHEMA options_audit;

CREATE TABLE options_audit.author (
  id BIGINT PRIMARY KEY,
  name TEXT NOT NULL
);

CREATE TABLE options_audit.authors (
  id BIGINT PRIMARY KEY,
  name TEXT NOT NULL
);

CREATE TABLE options_audit.option_items (
  id BIGINT PRIMARY KEY,
  note TEXT NOT NULL,
  tag TEXT NOT NULL,
  extra TEXT NOT NULL
);
