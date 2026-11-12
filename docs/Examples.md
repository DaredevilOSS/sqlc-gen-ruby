# Examples

The same example application for each database: a schema, queries that use every supported feature, and the code
the plugin generates from them. The generated code is committed, and the end-to-end tests run against it.

In each generated directory, `query_sql.rb` has the query methods, `models.rb` the table and enum models,
`connection.rb` the shared helpers, and the `.rbs` files their signatures
(see [The generated code](Generated-Code.md)).

## PostgreSQL (`pg`)

[Schema](../examples/authors/postgresql/schema.sql) · [Queries](../examples/authors/postgresql/query.sql) · [Generated code](../examples/pg) · [End-to-end tests](../tests/end2end_pg.rb)

Options:
```yaml
driver: pg
rubyVersion: "3.3"
generateTypes: true
generateGemfile: false
```

## MySQL (`mysql2`)

[Schema](../examples/authors/mysql/schema.sql) · [Queries](../examples/authors/mysql/query.sql) · [Generated code](../examples/mysql2) · [End-to-end tests](../tests/end2end_mysql2.rb)

Options:
```yaml
driver: mysql2
rubyVersion: "3.3"
generateTypes: true
generateGemfile: false
```

## SQLite (`sqlite3`)

[Schema](../examples/authors/sqlite/schema.sql) · [Queries](../examples/authors/sqlite/query.sql) · [Generated code](../examples/sqlite3) · [End-to-end tests](../tests/end2end_sqlite3.rb)

Options:
```yaml
driver: sqlite3
rubyVersion: "3.3"
generateTypes: true
generateGemfile: false
```
