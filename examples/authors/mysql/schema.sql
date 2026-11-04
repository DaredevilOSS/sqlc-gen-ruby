CREATE TABLE authors (
  id   BIGINT PRIMARY KEY AUTO_INCREMENT,
  name text      NOT NULL,
  bio  text
);

CREATE TABLE books (
  id BIGINT PRIMARY KEY AUTO_INCREMENT,
  name TEXT NOT NULL,
  author_id BIGINT NOT NULL,
  description TEXT,
  FOREIGN KEY (author_id) REFERENCES authors (id) ON DELETE CASCADE
);

CREATE TABLE extended_bios (
  author_name VARCHAR(100),
  name VARCHAR(100),
  bio_type ENUM('Autobiography', 'Biography', 'Memoir'),
  author_type SET('Author', 'Editor', 'Translator'),
  PRIMARY KEY (author_name, name)
);

CREATE TABLE regressions (
  id      bigint NOT NULL AUTO_INCREMENT PRIMARY KEY,
  `order` varchar(255) NOT NULL DEFAULT '',
  note    text,
  payload varbinary(16),
  -- enum values that are Ruby keywords or the enum module's own ALL constant
  step    ENUM('begin', 'end', 'all', 'nil', 'self', 'do'),
  -- :copyfrom (LOAD DATA) of JSON next to binary and unsigned values, INSERT IGNORE / REPLACE on a unique key
  code    varchar(32) UNIQUE,
  doc     json,
  flags   bit(8),
  amount  int unsigned
);
CREATE TABLE `MixedCaseCopies` (`Id` BIGINT NOT NULL PRIMARY KEY, `SomeValue` TEXT);

CREATE TABLE name_cases (
  id BIGINT NOT NULL PRIMARY KEY,
  `class` TEXT NOT NULL,
  `end` TEXT NOT NULL,
  `hash` TEXT NOT NULL,
  `method` TEXT NOT NULL,
  `count` INT NOT NULL,
  `camelCase` TEXT NOT NULL,
  `HTTPServer` TEXT NOT NULL,
  `initialize` TEXT NOT NULL
);

-- Tables whose models share their name with a Ruby core or library constant used by the generated code
-- (PgCodegen::Exception, ...): generated code refers to those constants as ::Exception, ::Thread, ...
CREATE TABLE exceptions (id BIGINT AUTO_INCREMENT PRIMARY KEY);
CREATE TABLE standard_errors (id BIGINT AUTO_INCREMENT PRIMARY KEY);
CREATE TABLE threads (id BIGINT AUTO_INCREMENT PRIMARY KEY);
CREATE TABLE processes (id BIGINT AUTO_INCREMENT PRIMARY KEY);
CREATE TABLE data (id BIGINT AUTO_INCREMENT PRIMARY KEY);
CREATE TABLE structs (id BIGINT AUTO_INCREMENT PRIMARY KEY);
CREATE TABLE sets (id BIGINT AUTO_INCREMENT PRIMARY KEY);
CREATE TABLE strings (id BIGINT AUTO_INCREMENT PRIMARY KEY);
CREATE TABLE integers (id BIGINT AUTO_INCREMENT PRIMARY KEY);
CREATE TABLE times (id BIGINT AUTO_INCREMENT PRIMARY KEY);
CREATE TABLE encodings (id BIGINT AUTO_INCREMENT PRIMARY KEY);
CREATE TABLE monitors (id BIGINT AUTO_INCREMENT PRIMARY KEY);
CREATE TABLE mutexes (id BIGINT AUTO_INCREMENT PRIMARY KEY);
CREATE TABLE connection_pools (id BIGINT AUTO_INCREMENT PRIMARY KEY);

-- Type coverage: one table per type family, written by one Insert and read by one Get query.

CREATE TABLE mysql_numeric_types (
  id BIGINT NOT NULL PRIMARY KEY,
  c_bool BOOL,
  c_boolean BOOLEAN,
  c_tinyint TINYINT,
  c_smallint SMALLINT,
  c_mediumint MEDIUMINT,
  c_int INT,
  c_integer INTEGER,
  c_bigint BIGINT,
  c_bigint_unsigned BIGINT UNSIGNED,
  c_serial SERIAL,
  c_decimal DECIMAL(2,1),
  c_dec DEC(2,1),
  c_numeric NUMERIC(2,1),
  c_fixed FIXED(2,1),
  c_decimal_wide DECIMAL(65, 30),
  c_float FLOAT,
  c_double DOUBLE,
  c_double_precision DOUBLE PRECISION
);

CREATE TABLE mysql_string_types (
  id BIGINT NOT NULL PRIMARY KEY,
  c_char CHAR,
  c_nchar NCHAR,
  c_national_char NATIONAL CHAR,
  c_varchar VARCHAR(10),
  c_tinytext TINYTEXT,
  c_text TEXT,
  c_mediumtext MEDIUMTEXT,
  c_longtext LONGTEXT,
  c_json JSON
);

CREATE TABLE mysql_datetime_types (
  id BIGINT NOT NULL PRIMARY KEY,
  c_date DATE,
  c_time TIME,
  c_datetime DATETIME,
  c_datetime_6 DATETIME(6),
  c_timestamp TIMESTAMP NULL,
  c_year YEAR
);

CREATE TABLE mysql_binary_types (
  id BIGINT NOT NULL PRIMARY KEY,
  c_bit BIT,
  c_bit_16 BIT(16),
  c_binary BINARY,
  c_varbinary VARBINARY(10),
  c_tinyblob TINYBLOB,
  c_blob BLOB,
  c_mediumblob MEDIUMBLOB,
  c_longblob LONGBLOB
);
