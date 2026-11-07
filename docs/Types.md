# Types and names

## Types

Types follow what the drivers return.

| SQL | Ruby |
|---|---|
| integers, floats | `Integer`, `Float` |
| `numeric` / `decimal` | `BigDecimal` |
| text | `String` |
| dates and times | `Date`, `Time` |
| network addresses | `IPAddr` |
| booleans | `true` / `false` |
| nullable columns and parameters | `T?` |

### PostgreSQL

* `json` / `jsonb` are parsed (`untyped`). A `String` passed to a `json` / `jsonb` parameter is JSON text
  (`'{"a":1}'`): pass `'"hi"'` or `'hi'.to_json` for a JSON string. Hashes, Arrays, numbers, `true` / `false` and `nil`
  are encoded for you.
* Arrays are `Array[T]` (`Array[Array[T]]` for `T[][]`); arrays of types the pg gem does not decode (`uuid[]`, enum
  arrays, ...) are `Array[String]`, also for types created after the connection was opened (a migration run while the
  application is up).
* Geometric, range, full-text, `hstore`, `ltree`, `timetz`, `reg*` and composite types are `String`s; domains and
  unknown types are `untyped`.
* A `Time` or `DateTime` parameter of a `timestamp` (without time zone) column (also in `:copyfrom` and batches) keeps
  its instant whatever its UTC offset: it is written in the process's local zone, the zone the pg gem reads `timestamp`
  values back in (PostgreSQL itself ignores the offset of a `timestamp` value). A `DateTime` of a `timestamptz` column
  keeps its instant too (the pg gem alone would send its date only); the RBS still declares `::Time`, the type the
  rows return. Elements of `timestamp[]` arrays are written as given.

### MySQL

* `JSON` columns and parameters are JSON text `String`s, as `mysql2` returns them.
* A `Time` / `DateTime` parameter (also in `:copyfrom`) keeps its instant whatever its UTC offset: it is written in
  the zone `mysql2` reads `DATETIME` / `TIMESTAMP` values back in, the process's local zone, or UTC for a client
  created with `database_timezone: :utc` (`connect(params.merge(database_timezone: :utc))`). The server also converts
  `TIMESTAMP` columns with the session `time_zone`, so keep that equal to the client's zone.

### SQLite

* Follows its [type affinity rules](https://www.sqlite.org/datatype3.html#determination_of_column_affinity)
  (`VARCHAR(255)` → `String`, `DECIMAL(10,5)` → `Float`, `UNSIGNED BIG INT` → `Integer`).
* `JSON` and `UUID` columns are `String`s, also when SQLite stored numeric-looking text as a number (`'42'` → `"42"`,
  in SQLite's spelling: `'1.50'` → `"1.5"`).
* The generated code uses `Monitor`: if you run Steep, add `library "monitor"` to your `Steepfile`. Code generated for
  a `rubyVersion` below 3.3 also uses `Timeout` (see [Transactions](Transactions.md)): add `library "timeout"` too.

### Time zones

A column without a time zone (PostgreSQL `timestamp`, MySQL `DATETIME`) stores the local wall-clock time, so an
instant in the hour repeated when the local zone falls back from daylight saving time (e.g. 02:30 on the last Sunday of
October in Europe/Berlin happens twice) reads back as the first of the two, one hour off for the second. Use
`timestamptz` / `TIMESTAMP`, or run the process in UTC (`TZ=UTC`), to keep every instant.

### Enums

Enums are `String`s, with constants in `models.rb` (`ExtendedBioType::MEMOIR`, `ExtendedBioType::ALL`). Values that are
not valid constant names still get one: `'end'` → `END_`, `'all'` → `ALL_`, `'2x'` → `VALUE_2X`, `'a b'` → `A_B`; values
that end up with the same name get `_2`, `_3`, ...

## Names

* Query methods and keyword arguments are snake_cased, with acronyms kept together (`MIN_ID` → `min_id`,
  `HTTPServer` → `http_server`); Ruby keywords get a trailing `_` (`end_:`).
* Row members use the column spelling reported by sqlc for the engine, except names that conflict with row methods,
  including the private ones `Data` / `Struct` call while building and copying rows (`class_`, `hash_`, `initialize_`):
  PostgreSQL and SQLite keep `"camelCase"` as `:camelCase`, while MySQL reports it as `:camelcase`. A column named
  `end` is the row member `:end` but the argument `end_:`. `Struct` rows (`rubyVersion` below 3.2) have more methods
  than `Data` rows, so more names get the `_`: a column `count` is `:count` from 3.2 but `:count_` below
  (`Struct#count` would otherwise be `Enumerable#count`); check the generated `.rbs` when changing `rubyVersion`.
* A result column without a usable name (`SELECT 1, now()`) is named by its position: `column_1`, `column_2`, ...
* A parameter used twice is one keyword when named with `sqlc.arg`; repeated `?` / `$n` of one column become `id:`,
  `id_2:`.
* Models may be named like Ruby or driver constants (tables `exceptions`, `data`, `threads`, `sets`, ...): the
  generated code and `.rbs` refer to those as `::Exception`, `::Data`, `::Thread`, ... so the models cannot shadow them.
* A table `authors` next to a table `author` keeps its plural model name (`Authors`). Query names that would replace a
  generated method (`Transaction`, `Initialize`, ...) are errors.
* SQLite: sqlc before 1.30 (including the pinned 1.27) reports a quoted table name with its quotes, so
  `CREATE TABLE "Items"` gives the model `Items` there and `Item` with sqlc 1.30 and later (PostgreSQL / MySQL give
  `Item` with any version). Use `rename` or `exactTableNames` to keep the name when upgrading sqlc.
