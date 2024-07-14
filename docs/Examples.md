# Examples
## Engine `postgresql`: [examples/pg](../examples/pg)

### [Schema](../examples/authors/postgresql/schema.sql) | [Queries](../examples/authors/postgresql/query.sql) | [End2End Test](../tests/end2end_pg.rb)

### Config
```yaml
driver: pg
rubyVersion: "3.3"
generateTypes: true
generateGemfile: false
```

## Engine `mysql`: [examples/mysql2](../examples/mysql2)

### [Schema](../examples/authors/mysql/schema.sql) | [Queries](../examples/authors/mysql/query.sql) | [End2End Test](../tests/end2end_mysql2.rb)

### Config
```yaml
driver: mysql2
rubyVersion: "3.3"
generateTypes: true
generateGemfile: false
```

## Engine `sqlite`: [examples/sqlite3](../examples/sqlite3)

### [Schema](../examples/authors/sqlite/schema.sql) | [Queries](../examples/authors/sqlite/query.sql) | [End2End Test](../tests/end2end_sqlite3.rb)

### Config
```yaml
driver: sqlite3
rubyVersion: "3.3"
generateTypes: true
generateGemfile: false
```

