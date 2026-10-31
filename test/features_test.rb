# frozen_string_literal: true

require_relative 'test_helper'

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
    assert_includes rbs, 'attr_reader param1: Array[Integer]'
    assert_includes rbs, 'attr_reader c_text_array: Array[String]?'
  end

  def test_unnamed_parameters_get_positional_names
    files = generate(load_request('pg'))
    assert_includes files.fetch('query_sql.rb'), 'class GetAuthorsByIdsAndNamesArgs < Data.define(:param1, :param2)'
  end

  def test_models_cover_tables_and_enums
    pg = generate(load_request('pg'))
    assert_includes pg.fetch('models.rb'), 'class Author < Data.define(:id, :name, :bio)'
    assert_includes pg.fetch('models.rb'), "AUTOBIOGRAPHY = \"Autobiography\""
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

  def test_unknown_types_in_queries_fail
    request = load_request('pg')
    query(request, 'GetAuthor').columns.first.type.name = 'geometry'
    assert_raises(RuntimeError) { generate(request) }
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
    assert_includes files.fetch('query_sql.rb'), "sql = GetAuthorsByIdsSql.sub('/*SLICE:ids*/?', slice_placeholders(get_authors_by_ids_args.ids))"
    assert_includes files.fetch('query_sql.rb'), 'query_params = [*get_authors_by_ids_args.ids]'
    assert_includes files.fetch('query_sql.rbs'), 'attr_reader ids: Array[Integer]'
    assert_includes files.fetch('query_sql.rbs'), 'def slice_placeholders: (Array[untyped]) -> String'
  end

  def test_slices_are_rejected_for_postgres
    request = load_request('pg')
    query(request, 'GetAuthorsByIds').params.first.column.is_sqlc_slice = true
    assert_raises(RuntimeError) { generate(request) }
  end

  def test_command_return_types
    rbs = generate(load_request('pg')).fetch('query_sql.rbs')
    assert_includes rbs, 'def update_author_bios: (UpdateAuthorBiosArgs) -> Integer'
    assert_includes rbs, 'def create_author_return_id: (CreateAuthorReturnIdArgs) -> Integer'
    assert_includes rbs, 'def create_book: (CreateBookArgs) -> String'
    assert_includes rbs, 'def copy_authors: (Array[CopyAuthorsArgs]) -> void'
    assert_includes rbs, 'def list_authors: -> Array[ListAuthorsRow]'
    assert_includes rbs, 'def transaction: [T] () { (self) -> T } -> T'
  end

  def test_pg_and_sqlite_execlastid_need_returning
    %w[pg sqlite3].each do |driver|
      request = load_request(driver)
      query(request, 'CreateBook').columns.clear
      assert_raises(RuntimeError, driver) { generate(request) }
    end
  end

  def test_mysql_copyfrom_adds_csv_helpers_and_gemfile_entry
    files = generate(load_request('mysql2', generateGemfile: true))
    assert_includes files.fetch('query_sql.rb'), "require 'csv'"
    assert_includes files.fetch('query_sql.rb'), 'def csv_line(values)'
    assert_includes files.fetch('Gemfile'), "gem 'csv'"
    refute_includes generate(load_request('pg', generateGemfile: true)).fetch('Gemfile'), 'csv'
  end

  def test_sqlite_and_mysql_close_prepared_statements
    %w[mysql2 sqlite3].each do |driver|
      assert_match(/ensure\n\t+stmt\.close\n/, generate(load_request(driver)).fetch('query_sql.rb'), driver)
    end
  end
end
