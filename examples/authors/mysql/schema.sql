CREATE TABLE authors (
  id   BIGINT PRIMARY KEY AUTO_INCREMENT,
  name text      NOT NULL,
  bio  text
);

CREATE TABLE node_mysql_types (
  c_bit BIT,
  c_tinyint TINYINT,
  c_bool BOOL,
  c_boolean BOOLEAN,
  c_smallint SMALLINT,
  c_mediumint MEDIUMINT,
  c_int INT,
  c_integer INTEGER,
  c_bigint BIGINT,
  c_serial SERIAL,
  c_decimal DECIMAL(2,1),
  c_dec DEC(2,1),
  c_numeric NUMERIC(2,1),
  c_fixed FIXED(2,1),
  c_float FLOAT,
  c_double DOUBLE,
  c_double_precision DOUBLE PRECISION,
  c_date DATE,
  c_time TIME,
  c_datetime DATETIME,
  c_timestamp TIMESTAMP,
  c_year YEAR,
  c_char CHAR,
  c_nchar NCHAR,
  c_national_char NATIONAL CHAR,
  c_varchar VARCHAR(10),
  c_binary BINARY,
  c_varbinary VARBINARY(10),
  c_tinyblob TINYBLOB,
  c_tinytext TINYTEXT,
  c_blob BLOB,
  c_text TEXT,
  c_mediumblob MEDIUMBLOB,
  c_mediumtext MEDIUMTEXT,
  c_longblob LONGBLOB,
  c_longtext LONGTEXT,
  /* c_enum ENUM('a', 'b', 'c'), */
  /* c_set SET('a', 'b', 'c'), */

  c_json JSON
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
  `order` varchar(255) NOT NULL,
  note    text,
  payload varbinary(16),
  -- enum values that are Ruby keywords or the enum module's own ALL constant
  step    ENUM('begin', 'end', 'all', 'nil', 'self', 'do')
);

CREATE TABLE copy_types (
  id     bigint NOT NULL PRIMARY KEY,
  code   varchar(32) NOT NULL UNIQUE,
  doc    json,
  flags  bit(8),
  amount int unsigned
);

CREATE TABLE mysql_binding_values (
  id BIGINT NOT NULL PRIMARY KEY,
  text_value LONGTEXT,
  blob_value LONGBLOB,
  signed_value BIGINT,
  unsigned_value BIGINT UNSIGNED,
  decimal_value DECIMAL(65, 30),
  float_value DOUBLE,
  date_value DATE,
  datetime_value DATETIME(6),
  datetime_2 DATETIME(6),
  bool_value BOOLEAN,
  nullable_value TEXT,
  bit_value BIT(16),
  year_value YEAR,
  time_value TIME,
  json_unicode JSON
);

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
