# frozen_string_literal: true

require_relative 'test_helper'
require 'sqlc_gen_ruby/code'

# Generator behaviour for the sqlc features the example schemas exercise (details of the runtime behaviour of the
# generated code are covered by the end-to-end tests under tests/).
class FeaturesTest < Minitest::Test
  include PluginHelper

  def query(request, name) = request.queries.find { |q| q.name == name }

  def test_nullable_columns_get_optional_types
    rbs = generate(load_request('pg')).fetch('query_sql.rbs')
    assert_match(/class GetAuthorRow\n\s+attr_reader id: Integer\n\s+attr_reader name: String\n\s+attr_reader bio: String\?/, rbs)
  end

  def test_overrides_replace_type_and_nullability
    overrides = [{ column: 'GetAuthor:bio', ruby_type: { type: 'Symbol', notNull: true } },
                 { column: '*:name', ruby_type: { type: 'Pathname', notNull: false } }]
    rbs = generate(load_request('pg', overrides: overrides)).fetch('query_sql.rbs')
    assert_match(/class GetAuthorRow\n.*\n\s+attr_reader name: Pathname\?\n\s+attr_reader bio: Symbol\n/, rbs)
    assert_match(/class ListAuthorsRow\n.*\n\s+attr_reader name: Pathname\?\n\s+attr_reader bio: String\?\n/, rbs)
  end

  def test_invalid_overrides_are_rejected
    assert_raises(RuntimeError) { generate(load_request('pg', overrides: [{ column: 'nocolon', ruby_type: {} }])) }
  end

  def test_array_parameters_and_columns
    rbs = generate(load_request('pg')).fetch('query_sql.rbs')
    assert_includes rbs, 'def get_authors_by_ids: (param1: Array[Integer]) -> Array[GetAuthorsByIdsRow]'
    assert_includes rbs, 'attr_reader c_text_array: Array[String]?'
  end

  def test_unnamed_parameters_get_positional_names
    files = generate(load_request('pg'))
    assert_includes files.fetch('query_sql.rb'), 'def get_authors_by_ids_and_names(param1:, param2:)'
  end

  def test_models_cover_tables_and_enums
    pg = generate(load_request('pg'))
    assert_includes pg.fetch('models.rb'), 'class Author < Data.define(:id, :name, :bio)'
    assert_includes pg.fetch('models.rb'), "AUTOBIOGRAPHY = 'Autobiography'"
    assert_includes pg.fetch('models.rb'), 'module ExtendedBioType'
    assert_includes pg.fetch('models.rbs'), 'attr_reader bio_type: String?'
    assert_includes pg.fetch('query_sql.rb'), "require_relative 'models'"
    mysql = generate(load_request('mysql2')).fetch('models.rb')
    assert_includes mysql, 'module ExtendedBiosBioType'
    assert_includes mysql, 'module ExtendedBiosAuthorType'
  end

  def test_models_fall_back_to_untyped_for_unknown_types
    request = load_request('pg')
    request.catalog.schemas.find { |s| s.name == 'public' }.tables.first.columns.first.type.name = 'geometry'
    assert_includes generate(request).fetch('models.rbs'), 'attr_reader id: untyped'
  end

  def test_unknown_types_in_queries_fall_back_to_untyped
    request = load_request('pg')
    query(request, 'GetAuthor').columns.first.type.name = 'geometry'
    query(request, 'GetAuthor').params.first.column.type.name = 'geometry'
    rbs = generate(request).fetch('query_sql.rbs')
    assert_includes rbs, "class GetAuthorRow\n    attr_reader id: untyped\n"
    assert_includes rbs, 'def get_author: (id: untyped) -> GetAuthorRow?'
  end

  def test_more_postgres_types_composites_and_domains
    rbs = generate(load_request('pg')).fetch('query_sql.rbs')
    %w[c_timetz c_tsvector c_point c_int4range c_dimensions].each { |c| assert_includes rbs, "attr_reader #{c}: String?" }
    assert_includes rbs, 'attr_reader c_oid: Integer?'
    assert_includes rbs, 'attr_reader c_positive: untyped' # sqlc does not send the base type of a domain
  end

  def test_sqlite_declared_types_follow_type_affinity
    rbs = generate(load_request('sqlite3')).fetch('query_sql.rbs')
    assert_match(/attr_reader c_varchar: String\?\n\s+attr_reader c_decimal: Float\?\n\s+attr_reader c_unsigned_big_int: Integer\?/, rbs)
    request = load_request('sqlite3')
    query(request, 'GetAuthor').columns.first.type.name = 'MEDIUMINT(4)'
    query(request, 'GetAuthor').columns[1].type.name = 'STRING'
    assert_match(/class GetAuthorRow\n\s+attr_reader id: Integer\n\s+attr_reader name: Float\n/, generate(request).fetch('query_sql.rbs'))
  end

  def test_execresult_returns_rows_affected_and_last_insert_id
    { 'pg' => 'ExecResult.new(result.cmd_tuples, nil)', 'mysql2' => 'ExecResult.new(stmt.affected_rows, client.last_id)',
      'sqlite3' => 'ExecResult.new(client.changes, client.last_insert_row_id)' }.each do |driver, line|
      files = generate(load_request(driver))
      assert_includes files.fetch('query_sql.rb'), line
      assert_includes files.fetch('query_sql.rb'), 'class ExecResult < Data.define(:rows_affected, :last_insert_id)'
      assert_includes files.fetch('query_sql.rbs'), 'def create_author_result: (name: String, bio: String?) -> ExecResult'
    end
  end

  def test_batch_commands_take_an_array_of_args
    %w[pg mysql2 sqlite3].each do |driver|
      files = generate(load_request(driver))
      rbs = files.fetch('query_sql.rbs')
      assert_includes rbs, 'def create_authors_batch: (Array[CreateAuthorsBatchArgs] rows) -> void'
      assert_includes rbs, 'def get_author_batch: (Array[GetAuthorBatchArgs] rows) -> Array[GetAuthorBatchRow?]'
      assert_includes rbs, 'def list_authors_by_name_batch: (Array[ListAuthorsByNameBatchArgs] rows) -> ' \
                           'Array[Array[ListAuthorsByNameBatchRow]]'
      assert_includes files.fetch('query_sql.rb'), 'class CreateAuthorsBatchArgs < Data.define(:name, :bio)'
      assert_includes files.fetch('query_sql.rb'), "rows.map do |args|\n"
    end
  end

  def test_embedded_tables_become_model_attributes
    rb = generate(load_request('pg')).fetch('query_sql.rb')
    assert_includes rb, 'class ListAllAuthorsBooksRow < Data.define(:author, :book)'
    assert_includes rb, 'class GetDuplicateAuthorsRow < Data.define(:author, :author2)'
    assert_includes rb, 'class GetAuthorsByBookNameRow < Data.define(:id, :name, :bio, :book)'
    assert_includes rb, 'GetDuplicateAuthorsRow.new(Author.new(row[0], row[1], row[2]), Author.new(row[3], row[4], row[5]))'
  end

  def test_slices_expand_at_runtime_and_are_array_typed
    files = generate(load_request('mysql2'))
    assert_includes files.fetch('query_sql.rb'), "sql = GET_AUTHORS_BY_IDS_SQL.gsub('/*SLICE:ids*/?', slice_placeholders(ids))"
    assert_includes files.fetch('query_sql.rb'), 'query_params = [*ids]'
    assert_includes files.fetch('query_sql.rbs'), 'def get_authors_by_ids: (ids: Array[Integer]) -> Array[GetAuthorsByIdsRow]'
    assert_includes files.fetch('query_sql.rbs'), 'def slice_placeholders: (Array[untyped] values) -> String'
  end

  def test_slices_are_rejected_for_postgres
    request = load_request('pg')
    query(request, 'GetAuthorsByIds').params.first.column.is_sqlc_slice = true
    assert_raises(RuntimeError) { generate(request) }
  end

  def test_command_signatures
    rbs = generate(load_request('pg')).fetch('query_sql.rbs')
    assert_includes rbs, 'def get_author: (id: Integer) -> GetAuthorRow?'
    assert_includes rbs, 'def update_author_bios: (bio: String?) -> Integer'
    assert_includes rbs, 'def create_author_return_id: (name: String, bio: String?) -> Integer'
    assert_includes rbs, 'def create_book: (name: String, author_id: Integer) -> String'
    assert_includes rbs, 'def copy_authors: (Array[CopyAuthorsArgs] rows) -> void'
    assert_includes rbs, 'def list_authors: -> Array[ListAuthorsRow]'
    assert_includes rbs, 'def delete_author: (id: Integer) -> void'
    assert_includes rbs, 'def transaction: [T] (?isolation: (:read_uncommitted | :read_committed | :repeatable_read | :serializable)?) { (self) -> T } -> T'
  end

  def test_named_nullable_parameters_are_optional_keywords
    files = generate(load_request('pg'))
    assert_includes files.fetch('query_sql.rb'), 'def get_author_by_name_pattern(name_pattern: nil)'
    assert_includes files.fetch('query_sql.rbs'), 'def get_author_by_name_pattern: (?name_pattern: String?) -> Array[GetAuthorByNamePatternRow]'
    # a plain nullable INSERT column has to be passed explicitly
    assert_includes files.fetch('query_sql.rb'), 'def create_author_return_id(name:, bio:)'
  end

  def test_reserved_words_and_camel_case_parameter_names
    request = load_request('pg')
    query(request, 'GetAuthor').params.first.column.name = 'class'
    query(request, 'DeleteAuthor').params.first.column.name = 'authorId'
    rb = generate(request).fetch('query_sql.rb')
    assert_includes rb, 'def get_author(class_:)'
    assert_includes rb, 'def delete_author(author_id:)'
    assert_includes rb, 'query_params = [class_]'
  end

  def test_pg_and_sqlite_execlastid_need_returning
    %w[pg sqlite3].each do |driver|
      request = load_request(driver)
      query(request, 'CreateBook').columns.clear
      assert_raises(RuntimeError, driver) { generate(request) }
    end
  end

  def test_mysql_copyfrom_writes_its_own_csv
    files = generate(load_request('mysql2', generateGemfile: true))
    refute_includes files.fetch('query_sql.rb'), "require 'csv'"
    assert_includes files.fetch('query_sql.rb'), "require 'tempfile'"
    assert_includes files.fetch('query_sql.rb'), 'def csv_line(values)'
    assert_equal "# frozen_string_literal: true\n\nsource 'https://rubygems.org'\n\ngem 'connection_pool'\ngem 'mysql2'\n",
                 files.fetch('Gemfile')
  end

  def test_sqlite_and_mysql_close_prepared_statements
    %w[mysql2 sqlite3].each do |driver|
      assert_match(/ensure\n\s+stmt\.close\n/, generate(load_request(driver)).fetch('query_sql.rb'), driver)
    end
  end

  # ---- Ruby style of the generated code ------------------------------------------------------------------------

  def test_generated_ruby_is_formatted_like_ruby
    %w[pg mysql2 sqlite3].each do |driver|
      generate(load_request(driver)).each do |name, contents|
        refute_includes contents, "\t", "#{driver}/#{name} contains tabs"
        assert_equal contents.lines.first.chomp, '# frozen_string_literal: true' if name.end_with?('.rb')
        assert contents.end_with?("\n"), "#{driver}/#{name} should end with a newline"
        outside_heredocs = contents.gsub(/<<~'(\w+)'\n.*?^\s*\1$/m, 'HEREDOC')
        refute_match(/[ ]+$/, outside_heredocs, "#{driver}/#{name} has trailing whitespace")
        next unless name.end_with?('.rb')

        assert_equal 0, ruby_syntax_check(contents), "#{driver}/#{name} is not valid Ruby"
      end
    end
  end

  def ruby_syntax_check(source)
    _out, _err, status = Open3.capture3(RbConfig.ruby, '-c', stdin_data: source)
    status.exitstatus
  end

  def test_sql_is_a_frozen_raw_heredoc
    rb = generate(load_request('pg')).fetch('query_sql.rb')
    assert_includes rb, "GET_AUTHOR_SQL = <<~'SQL'\n    SELECT id, name, bio FROM authors\n    WHERE id = $1 LIMIT 1\n  SQL"
  end

  def test_heredoc_terminator_never_collides_with_the_query
    request = load_request('sqlite3')
    query(request, 'GetAuthor').text = "SELECT 1\nSQL\nFROM x"
    assert_includes generate(request).fetch('query_sql.rb'), "<<~'SQL_'"
  end

  def test_query_comments_become_doc_comments
    rb = generate(load_request('pg')).fetch('query_sql.rb')
    assert_includes rb, "    # Returns the author with the given id, or nil when there is none.\n    def get_author(id:)"
  end

  def test_statements_are_named_after_the_query_class
    rb = generate(load_request('pg')).fetch('query_sql.rb')
    assert_includes rb, "client.exec_prepared('query_sql_get_author', query_params)"
  end

  def test_pg_can_skip_prepared_statements
    rb = generate(load_request('pg', preparedStatements: false)).fetch('query_sql.rb')
    assert_includes rb, 'client.exec_params(GET_AUTHOR_SQL, query_params)'
    refute_includes rb, 'client.prepare('
  end

  def test_module_name_option
    files = generate(load_request('pg', moduleName: 'MyApp::Db'))
    files.each { |name, contents| assert_includes contents, "module MyApp\n  module Db\n" if name.end_with?('.rb', '.rbs') }
    assert_raises(RuntimeError) { generate(load_request('pg', moduleName: 'not a constant')) }
  end

  def test_set_is_only_required_before_ruby_3_2
    assert_includes generate(load_request('pg', rubyVersion: '3.1')).fetch('query_sql.rb'), "require 'set'"
    refute_includes generate(load_request('pg')).fetch('query_sql.rb'), "require 'set'"
  end

  # Ruby < 3.2 has no Data: rows are keyword_init Structs, built with keywords like Data rows.
  def test_struct_classes_are_valid_and_usable
    files = generate(load_request('pg', rubyVersion: '3.1'))
    assert_includes files.fetch('models.rb'), 'Author = Struct.new(:id, :name, :bio, keyword_init: true)'
    assert_includes files.fetch('query_sql.rb'), 'GetAuthorRow = Struct.new(:id, :name, :bio, keyword_init: true)'
    assert_includes files.fetch('query_sql.rb'), "GetAuthorRow.new(id: row['id'], name: row['name'], bio: row['bio'])"
    assert_includes files.fetch('models.rbs'), "class Author < ::Struct[untyped]\n"
    scope = Module.new
    scope.module_eval(files.fetch('models.rb'))
    author = scope::PgCodegen::Author.new(id: 1, name: 'a', bio: nil)
    assert_equal({ id: 1, name: 'a', bio: nil }, author.to_h)
    assert_equal 'a', author.name
  end

  def test_data_classes_are_usable
    skip 'Data needs Ruby 3.2' unless defined?(Data)
    files = generate(load_request('pg'))
    scope = Module.new
    scope.module_eval(files.fetch('models.rb'))
    author = scope::PgCodegen::Author.new(id: 1, name: 'a', bio: nil)
    assert_equal 'a', author.name
    assert author.frozen?
  end

  # ---- Ruby conventions ----------------------------------------------------------------------------------------

  def test_bang_finders_for_one_queries
    %w[pg mysql2 sqlite3].each do |driver|
      files = generate(load_request(driver))
      assert_includes files.fetch('query_sql.rb'), "def get_author!(...)\n      get_author(...) || raise(NotFound, 'GetAuthor returned no row')"
      assert_includes files.fetch('query_sql.rb'), 'class NotFound < StandardError'
      assert_includes files.fetch('query_sql.rbs'), 'def get_author!: (id: Integer) -> GetAuthorRow'
      refute_includes files.fetch('query_sql.rb'), 'def list_authors!' # only :one queries
    end
  end

  def test_logger_support
    %w[pg mysql2 sqlite3].each do |driver|
      rb = generate(load_request(driver)).fetch('query_sql.rb')
      assert_includes rb, 'def initialize(db, logger: nil)'
      assert_includes rb, "with_client('get_author') do |client|"
      assert_includes rb, 'def instrument(name)'
      assert_includes generate(load_request(driver)).fetch('query_sql.rbs'), 'def instrument: [T] (String name) { () -> T } -> T'
    end
    assert_includes generate(load_request('pg')).fetch('query_sql.rb'), 'def self.connect(pg_params, logger: nil, **pool_options)'
  end

  def test_query_names_cannot_replace_generated_methods
    %w[Transaction Initialize Connect WithClient Hash].each do |name|
      request = load_request('pg')
      query(request, 'DeleteAuthor').name = name
      error = assert_raises(RuntimeError) { generate(request) }
      assert_includes error.message, "query #{name}: method"
    end
  end

  def test_query_file_names_become_valid_constants
    request = load_request('sqlite3')
    request.queries.each { |q| q.filename = 'user-queries.sql' }
    files = generate(request)
    assert_includes files.fetch('user_queries_sql.rb'), 'class UserQueriesSql'
    assert_equal 0, ruby_syntax_check(files.fetch('user_queries_sql.rb'))
  end

  def test_query_files_writing_the_same_file_are_rejected
    request = load_request('sqlite3')
    request.queries.first.filename = 'user-queries.sql'
    request.queries.last.filename = 'user_queries.sql'
    assert_raises(RuntimeError) { generate(request) }
  end


  def test_tables_with_the_same_singular_get_distinct_models
    request = load_request('pg')
    tables = request.catalog.schemas.find { |s| s.name == 'public' }.tables
    author = tables.find { |t| t.rel.name == 'authors' }
    tables << Plugin::Table.new(rel: Plugin::Identifier.new(name: 'author'), columns: author.columns)
    models = generate(request).fetch('models.rb')
    assert_includes models, 'class Authors < Data.define(:id, :name, :bio)'
    assert_includes models, 'class Author < Data.define(:id, :name, :bio)'
    assert_equal 0, ruby_syntax_check(models)
  end

  def test_repeated_parameter_names_get_a_suffix
    files = generate(load_request('pg'))
    assert_includes files.fetch('query_sql.rb'), 'def list_authors_between_ids(id:, id_2:)'
    assert_includes files.fetch('query_sql.rbs'), 'def list_authors_between_ids: (id: Integer, id_2: Integer) -> Array[ListAuthorsBetweenIdsRow]'
  end

  def test_outer_join_embeds_are_optional
    files = generate(load_request('pg'))
    assert_includes files.fetch('query_sql.rbs'), "attr_reader author: Author?\n    attr_reader book: Book?"
    assert_includes files.fetch('query_sql.rb'), 'row[3].nil? && row[4].nil? && row[5].nil? ? nil : Book.new('
    assert_includes files.fetch('query_sql.rbs'), "class ListAllAuthorsBooksRow\n    attr_reader author: Author\n"
  end

  def test_multi_dimensional_arrays
    assert_includes generate(load_request('pg')).fetch('query_sql.rbs'),
                    'attr_reader c_integer_matrix: Array[Array[Integer]]?'
  end

  def test_table_column_and_db_type_overrides_apply_to_models_and_rows
    overrides = [{ column: 'authors.bio', ruby_type: { type: 'Symbol' } },
                 { column: '*:c_uuid', ruby_type: { type: 'Pathname', notNull: true } },
                 { db_type: 'jsonb', ruby_type: { type: 'Hash[String, untyped]' } }]
    files = generate(load_request('pg', overrides: overrides))
    assert_includes files.fetch('models.rbs'), "attr_reader bio: Symbol?\n"
    assert_includes files.fetch('models.rbs'), 'attr_reader c_uuid: Pathname'
    assert_includes files.fetch('models.rbs'), 'attr_reader c_jsonb: Hash[String, untyped]?'
    assert_match(/class GetAuthorRow\n.*\n.*\n\s+attr_reader bio: Symbol\?/, files.fetch('query_sql.rbs'))
    assert_includes files.fetch('query_sql.rbs'), 'attr_reader c_uuid: Pathname'
  end

  def test_rename_and_exact_table_names
    files = generate(load_request('pg', rename: { 'authors' => 'Writer', 'bio' => 'biography' }))
    assert_includes files.fetch('models.rb'), 'class Writer < Data.define(:id, :name, :biography)'
    assert_includes files.fetch('query_sql.rb'), 'class GetAuthorRow < Data.define(:id, :name, :biography)'
    assert_includes files.fetch('query_sql.rb'), "GetAuthorRow.new(row['id'], row['name'], row['bio'])"
    assert_includes files.fetch('query_sql.rb'), 'Writer.new(row[0], row[1], row[2])'
    assert_includes generate(load_request('pg', exactTableNames: true)).fetch('models.rb'), 'class Authors < Data.define'
    assert_raises(RuntimeError) { generate(load_request('pg', rename: { 'authors' => 'writer' })) }
  end

  def test_global_options_are_merged_under_plugin_options
    request = load_request('pg')
    request.global_options = JSON.generate(moduleName: 'Global::Db', generateTypes: false,
                                           overrides: [{ column: '*:bio', ruby_type: { type: 'Symbol' } }])
    files = generate(request)
    assert_includes files.fetch('query_sql.rb'), "module Global\n  module Db\n"
    assert_includes files.keys, 'query_sql.rbs' # generateTypes: true in the plugin options wins
    assert_match(/class GetAuthorRow\n.*\n.*\n\s+attr_reader bio: Symbol\?/, files.fetch('query_sql.rbs'))
  end

  def test_engine_must_match_the_driver
    request = load_request('pg')
    request.settings = Plugin::Settings.new(engine: 'mysql')
    error = assert_raises(RuntimeError) { generate(request) }
    assert_includes error.message, 'driver pg needs engine: postgresql (this sql block uses mysql)'
    request.settings.engine = 'postgresql'
    generate(request)
  end

  def test_table_column_and_enum_comments_become_doc_comments
    files = generate(load_request('pg'))
    assert_includes files.fetch('models.rb'), "  # People who wrote at least one book.\n  class Author < Data.define"
    assert_includes files.fetch('models.rbs'), "    # Short biography, NULL when unknown.\n    attr_reader bio: String?"
    assert_includes files.fetch('models.rb'), "  # Kinds of biographies.\n  module ExtendedBioType"
  end

  # ---- regressions (examples/authors/*: the `regressions` table) -----------------------------------------------

  def test_reused_and_repeated_parameters_get_one_keyword_each
    rb = generate(load_request('mysql2')).fetch('query_sql.rb')
    assert_includes rb, "def count_regressions_by_text(term:)\n"
    assert_includes rb, 'query_params = [term, term]'
    assert_includes rb, 'def list_regressions_by_ids(id:, id_2:, id_3:)'
  end

  def test_mysql_rows_are_read_by_position
    rb = generate(load_request('mysql2')).fetch('query_sql.rb')
    assert_includes rb, 'CountRegressionsByTextRow.new(row[0])'
    refute_includes rb, "row['"
  end

  def test_sqlite_types_with_modifiers_and_untyped_expressions
    files = generate(load_request('sqlite3'))
    assert_match(/class Regression\n\s+attr_reader id: Integer\n\s+attr_reader order: String\n\s+attr_reader price: Float\?/,
                 files.fetch('models.rbs'))
    assert_includes files.fetch('query_sql.rbs'), 'attr_reader max_price: untyped'
  end

  def test_casted_narg_is_optional
    assert_includes generate(load_request('pg')).fetch('query_sql.rbs'),
                    'def list_regressions: (?order_name: String?) -> Array[ListRegressionsRow]'
  end

  def test_copyfrom_quotes_identifiers
    assert_includes generate(load_request('pg')).fetch('query_sql.rb'), 'COPY "regressions" ("id", "order", "payload", "doc")'
    assert_includes generate(load_request('mysql2')).fetch('query_sql.rb'), 'INTO TABLE `regressions`'
    assert_includes generate(load_request('sqlite3')).fetch('query_sql.rb'), 'INSERT INTO "regressions" ("order", "price")'
  end

  def test_pg_encodes_bytea_json_and_string_arrays
    rb = generate(load_request('pg')).fetch('query_sql.rb')
    assert_includes rb, 'encode_bytea(payload),'
    assert_includes rb, 'encode_json(doc),'
    assert_includes rb, 'encode_array(bio_types)'
    assert_includes rb, 'def encode_array(value, kind = :value)'
    noprep = generate(load_request('pg', preparedStatements: false)).fetch('query_sql.rb')
    assert_includes noprep, 'encode_array(bio_types)'
  end

  def test_transactions_finish_on_non_local_exits
    %w[pg mysql2 sqlite3].each do |driver|
      assert_includes generate(load_request(driver)).fetch('query_sql.rb'), "Thread.current.status == 'aborting'", driver
    end
  end

  def test_parameters_named_like_generated_locals_are_renamed
    request = load_request('pg')
    query(request, 'GetAuthor').params.first.column.name = 'client'
    assert_includes generate(request).fetch('query_sql.rb'), "def get_author(client_:)\n"
  end

  def test_db_type_overrides_also_type_array_elements
    overrides = [{ db_type: 'uuid', ruby_type: { type: 'UUIDString' } }]
    rbs = generate(load_request('pg', overrides: overrides)).fetch('query_sql.rbs')
    assert_includes rbs, 'attr_reader uids: Array[UUIDString]?'
  end

  def test_batch_parameters_are_encoded_like_other_parameters
    request = load_request('pg')
    query(request, 'CreateAuthorsBatch').params[1].column.type.name = 'bytea'
    assert_includes generate(request).fetch('query_sql.rb'), 'query_params = [args.name, encode_bytea(args.bio)]'
  end

  def test_sqlite_json_and_uuid_declarations_are_strings
    request = load_request('sqlite3')
    query(request, 'GetAuthor').columns[1].type.name = 'JSON'
    query(request, 'GetAuthor').columns[2].type.name = 'UUID'
    assert_match(/class GetAuthorRow\n\s+attr_reader id: Integer\n\s+attr_reader name: String\n\s+attr_reader bio: String\?/,
                 generate(request).fetch('query_sql.rbs'))
  end

  def test_snake_case_keeps_acronyms_together
    { 'MIN_ID' => 'min_id', 'ABC' => 'abc', 'HTTPServer' => 'http_server', 'UserId' => 'user_id',
      'getHTTPResponse2Code' => 'get_http_response2_code', 'authorID' => 'author_id' }.each do |name, snake|
      assert_equal snake, SqlcGenRuby::Code.snake_case(name)
    end
  end

  def test_copyfrom_keeps_or_rejects_conflict_clauses
    sqlite = generate(load_request('sqlite3')).fetch('query_sql.rb')
    assert_includes sqlite, 'INSERT OR REPLACE INTO "tags"'
    assert_includes sqlite, 'ON CONFLICT (name) DO UPDATE SET uses = tags.uses + excluded.uses'
    mysql = generate(load_request('mysql2')).fetch('query_sql.rb')
    assert_includes mysql, "IGNORE INTO TABLE `copy_types`"
    assert_includes mysql, "REPLACE INTO TABLE `copy_types`"
    { 'pg' => ' ON CONFLICT DO NOTHING', 'mysql2' => ' ON DUPLICATE KEY UPDATE bio = bio',
      'sqlite3' => ' ON CONFLICT (name) DO UPDATE SET bio = ?' }.each do |driver, tail|
      request = load_request(driver)
      query(request, 'CopyAuthors').text += tail
      error = assert_raises(StandardError, driver) { generate(request) }
      assert_includes error.message, 'CopyAuthors', driver
    end
  end

  def test_nested_transactions_reject_isolation_and_mode
    { 'pg' => 'isolation:', 'mysql2' => 'isolation:', 'sqlite3' => 'mode:' }.each do |driver, option|
      assert_includes generate(load_request(driver)).fetch('query_sql.rb'),
                      "raise ArgumentError, '#{option} cannot be set on a nested transaction'"
    end
  end

  def test_pg_encodes_float_and_array_parameters_as_text
    rb = generate(load_request('pg')).fetch('query_sql.rb')
    assert_includes rb, 'encode_float(args.ratio)'
    assert_includes rb, 'encode_array(args.blobs, :bytea)'
    assert_includes rb, 'encode_array(args.docs, :json)'
    assert_includes rb, 'queries[TrueClass] = queries[FalseClass] = PG::TextEncoder::Boolean.new(oid: 16)'
  end

  def test_mysql_copyfrom_converts_json_columns_from_binary
    rb = generate(load_request('mysql2')).fetch('query_sql.rb')
    assert_includes rb, '(`id`, `code`, @sqlc_v2, `flags`, `amount`) SET `doc` = CONVERT(@sqlc_v2 USING utf8mb4)'
  end

  def test_schema_names_breaking_naming_cops_are_exempted_where_they_occur
    request = load_request('pg')
    get_author = query(request, 'GetAuthor')
    get_author.columns[1].name = 'UserId'
    get_author.columns[2].name = 'naïve'
    get_author.params.first.column.name = 'm'
    code = generate(request).fetch('query_sql.rb')
    assert_match(/# rubocop:disable Naming\/MethodName\n\s+class GetAuthorRow < Data.define\(:id, :UserId, :naïve\)\n\s+end\n\s+# rubocop:enable/, code)
    assert_match(/# rubocop:disable Naming\/MethodParameterName\n\s+def get_author\(m:\)/, code)
    assert_equal 1, code.scan('rubocop:disable Naming/MethodParameterName').size
    out, status = rubocop(code)
    assert status.success?, out
  end

  def rubocop(source)
    exe = begin
      Gem.bin_path('rubocop', 'rubocop')
    rescue Gem::GemNotFoundException
      skip 'rubocop not installed'
    end
    out, _err, status = Open3.capture3(RbConfig.ruby, exe, '--stdin', 'examples/pg/query_sql.rb',
                                       '--format', 'emacs', stdin_data: source, chdir: ROOT)
    [out, status]
  end

  def test_columns_become_valid_non_overriding_attributes
    request = load_request('pg')
    columns = query(request, 'GetAuthor').columns
    columns[1].name = 'Weird Name'
    columns[2].name = 'hash'
    assert_includes generate(request).fetch('query_sql.rb'), 'class GetAuthorRow < Data.define(:id, :weird_name, :hash_)'
  end

  def test_query_method_colliding_with_a_generated_method_is_an_error
    request = load_request('pg')
    query(request, 'GetAuthor').name = 'Transaction'
    assert_raises(RuntimeError) { generate(request) }
  end

  def test_constant_defined_twice_is_an_error
    request = load_request('pg')
    request.catalog.schemas.flat_map(&:tables).find { |t| t.rel.name == 'authors' }.rel.name = 'get_author_rows'
    assert_raises(RuntimeError) { generate(request) }
  end

  def test_nested_module_name_is_self_contained
    files = generate(load_request('pg', moduleName: 'MyApp::Db', rubyVersion: '3.1'))
    scope = Module.new
    scope.module_eval(files.fetch('models.rb'))
    assert scope::MyApp::Db::Author
  end

  def test_unknown_and_misplaced_options_are_errors
    assert_raises(RuntimeError) { generate(load_request('pg', moduleNmae: 'Db')) }
    assert_raises(RuntimeError) { generate(load_request('mysql2', preparedStatements: false)) }
    generate(load_request('pg', rubyVersion: '3.4'))
  end
end
