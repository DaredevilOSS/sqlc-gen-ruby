# Types

The generated code does not convert values: a column has the Ruby class its driver gem returns, and the `.rbs`
declares that class. Nullable columns and parameters are `T?`.

To declare a different type for a column, use [`overrides`](Options.md#overrides).

## Type mapping

| SQL | PostgreSQL | MySQL | SQLite |
|---|---|---|---|
| integers | `Integer` | `Integer` (also `YEAR`) | `Integer` |
| `real`, `float`, `double` | `Float` | `Float` | `Float` |
| `numeric`, `decimal` | `BigDecimal` | `BigDecimal` | `Float` |
| `boolean` | `true` / `false` | `Integer` (0 / 1) | `Integer` (0 / 1) |
| text (`char`, `varchar`, `text`, ...) | `String` | `String` | `String` |
| binary (`bytea`, `blob`, `binary`, ...) | `String` | `String` | `String` |
| `date` | `Date` | `Date` | `String` |
| `timestamp`, `timestamptz`, `datetime` | `Time` | `Time` | `String` |
| `time` | `String` | `Time` | `String` |
| JSON | parsed (`untyped`) | `String` (JSON text) | `String` (JSON text) |
| `uuid` | `String` | | `String` |
| enums | `String` | `String` (`ENUM`, `SET`) | |
| arrays | `Array[T]` | | |
| `inet`, `cidr` | `IPAddr` | | |
| `bit` | `String` | `String` | |

### PostgreSQL

* **JSON:** `json` / `jsonb` columns are parsed. For a parameter, Hashes, Arrays, numbers, `true` / `false` and `nil`
  are encoded for you. A `String` is taken as JSON text (`'{"a":1}'`), so pass `'"hi"'` or `'hi'.to_json` for a JSON
  string.
* **Arrays** are `Array[T]`, and `Array[Array[T]]` for `T[][]`. Arrays of types the pg gem does not decode (`uuid[]`,
  enum arrays, ...) are `Array[String]`, also for types created after the connection was opened (a migration that
  runs while the application is up).
* **`String`:** `money`, `interval`, `xml`, `macaddr`, geometric, range, full-text, `hstore`, `ltree`, `timetz`,
  `reg*` and composite types.
* **`untyped`:** domains and types the plugin does not know.

### MySQL

* `BOOLEAN` is `TINYINT(1)`, so it is an `Integer`.
* `JSON` columns and parameters are JSON text, as `mysql2` returns them.

### SQLite

SQLite has no fixed column types: the declared type only gives a column an
[affinity](https://www.sqlite.org/datatype3.html#determination_of_column_affinity), and the plugin follows the same
rules (`VARCHAR(255)` → `String`, `DECIMAL(10,5)` → `Float`, `UNSIGNED BIG INT` → `Integer`).

* Dates, times and booleans are stored as text or numbers, so they are `String` or `Integer`.
* A `NUMERIC` / `DECIMAL` column is declared `Float`, but SQLite can return an `Integer` (it stores `5.0` as `5`).
* `JSON` and `UUID` columns are always `String`s, also when SQLite stored numeric-looking text as a number. The text
  then comes back in SQLite's spelling: `'42'` → `"42"`, `'1.50'` → `"1.5"`.

## Dates and time zones

A `Time` or `DateTime` parameter keeps its instant whatever its UTC offset, also in `:copyfrom` and batches:

* **PostgreSQL `timestamp`** (without time zone): the value is written in the process's local zone, the zone the pg
  gem reads `timestamp` values back in. Elements of `timestamp[]` arrays are written as given.
* **PostgreSQL `timestamptz`:** a `DateTime` keeps its instant too. The RBS declares `::Time`, the class rows return.
* **MySQL `DATETIME` / `TIMESTAMP`:** the value is written in the zone `mysql2` reads values back in: the process's
  local zone, or UTC for a client created with `database_timezone: :utc`. The server also converts `TIMESTAMP` columns
  with the session `time_zone`, so keep that equal to the client's zone.

**Daylight saving time.** A column without a time zone (PostgreSQL `timestamp`, MySQL `DATETIME`) stores the local
wall-clock time. When the local zone falls back from daylight saving time, one hour happens twice (02:30 on the last
Sunday of October in Europe/Berlin), and an instant in the second of the two reads back as the first, one hour off.
Use `timestamptz` / `TIMESTAMP`, or run the process in UTC (`TZ=UTC`), to keep every instant.

## Enums

An enum column is a `String`. `models.rb` has a module of constants for each enum:

```ruby
PgCodegen::ExtendedBioType::MEMOIR   # => "Memoir"
PgCodegen::ExtendedBioType::ALL      # => ["Autobiography", "Biography", "Memoir"]
```

On PostgreSQL the module is named after the enum type. MySQL enums belong to a column, so the module is named after
the table and column: `Mysql2Codegen::ExtendedBiosBioType`. A MySQL `SET` column gets constants the same way.

Values that are not valid constant names still get a constant:

| Value | Constant |
|---|---|
| `'end'` | `END_` |
| `'all'` | `ALL_` |
| `'2x'` | `VALUE_2X` |
| `'a b'` | `A_B` |

Values that end up with the same name get `_2`, `_3`, ...
