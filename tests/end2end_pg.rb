#!/usr/bin/env ruby
gem 'minitest'     # ensures using the gem, and not the built-in MT
require 'minitest/autorun'
require 'bigdecimal'
require 'ipaddr'
require 'securerandom'
require_relative 'consts'
require_relative 'rbs_types'
require_relative '../examples/pg/query_sql'

# End-to-end tests of the code generated for examples/authors/postgresql, against a real PostgreSQL server.
class TestPg < Minitest::Test
  include PgCodegen

  def setup
    pg_params = {
      'dbname' => ENV['DB_NAME'],
      'host' => ENV['POSTGRES_HOST'],
      'port' => ENV['POSTGRES_PORT'], # optional
      'user' => ENV['DB_USER'],
      'password' => ENV['DB_PASS']
    }.compact
    @query_sql = QuerySql.new({}, pg_params)
    @query_sql.truncate_authors # cascades to books
    @query_sql.truncate_extended_bios
    @query_sql.truncate_extra_types
  end

  def create_author(name, bio = nil)
    @query_sql.create_author_return_id(CreateAuthorReturnIdArgs.new(name: name, bio: bio))
  end

  # ---- :one / :many / :exec -------------------------------------------------------------------------------------

  def test_flow
    first = @query_sql.create_author(CreateAuthorArgs.new(name: Consts::BOJACK_AUTHOR, bio: Consts::BOJACK_THEME))
    assert_equal CreateAuthorRow.new(first.id, Consts::BOJACK_AUTHOR, Consts::BOJACK_THEME), first
    second = @query_sql.create_author(CreateAuthorArgs.new(name: Consts::DR_SEUSS_AUTHOR, bio: Consts::DR_SEUSS_QUOTE))

    assert_equal GetAuthorRow.new(first.id, Consts::BOJACK_AUTHOR, Consts::BOJACK_THEME),
                 @query_sql.get_author(GetAuthorArgs.new(id: first.id))
    assert_nil @query_sql.get_author(GetAuthorArgs.new(id: -1))
    assert_equal [second.name, first.name].sort, @query_sql.list_authors.map(&:name).sort

    @query_sql.delete_author(DeleteAuthorArgs.new(id: first.id))
    assert_equal [ListAuthorsRow.new(second.id, Consts::DR_SEUSS_AUTHOR, Consts::DR_SEUSS_QUOTE)],
                 @query_sql.list_authors
  end

  def test_nullable_columns_round_trip_nil
    id = create_author('no bio', nil)
    assert_nil @query_sql.get_author(GetAuthorArgs.new(id: id)).bio
  end

  def test_one_on_empty_table_returns_nil
    assert_nil @query_sql.test
  end

  # ---- :execlastid / :execrows -----------------------------------------------------------------------------------

  def test_execlastid_returns_the_returning_column
    first = create_author('a')
    second = create_author('b')
    assert_kind_of Integer, first
    assert_equal first + 1, second
  end

  def test_execlastid_with_uuid_key
    author_id = create_author('a')
    book_id = @query_sql.create_book(CreateBookArgs.new(name: 'book', author_id: author_id))
    assert_match(/\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/, book_id)
  end

  def test_execrows_returns_affected_row_count
    create_author('with bio', 'bio')
    create_author('with bio 2', 'bio')
    create_author('without bio', nil)
    assert_equal 2, @query_sql.update_author_bios(UpdateAuthorBiosArgs.new(bio: 'new bio'))
    assert_equal 0, (@query_sql.truncate_authors; @query_sql.update_author_bios(UpdateAuthorBiosArgs.new(bio: 'x')))
  end

  # ---- sqlc.arg / sqlc.narg --------------------------------------------------------------------------------------

  def test_named_args_limit_and_offset
    %w[a b c d].each { |name| create_author(name) }
    page = @query_sql.list_authors_paged(ListAuthorsPagedArgs.new(limit: 2, offset: 1))
    assert_equal %w[b c], page.map(&:name)
  end

  def test_nullable_named_arg
    %w[abc abd xyz].each { |name| create_author(name) }
    all = @query_sql.get_author_by_name_pattern(GetAuthorByNamePatternArgs.new(name_pattern: nil))
    assert_equal 3, all.size
    ab = @query_sql.get_author_by_name_pattern(GetAuthorByNamePatternArgs.new(name_pattern: 'ab%'))
    assert_equal %w[abc abd], ab.map(&:name).sort
  end

  # ---- array parameters (PostgreSQL has no sqlc.slice) -----------------------------------------------------------

  def test_array_parameters
    ids = %w[a b c].map { |name| create_author(name) }
    assert_equal ids.first(2).sort,
                 @query_sql.get_authors_by_ids(GetAuthorsByIdsArgs.new(param1: ids.first(2))).map(&:id).sort
    assert_empty @query_sql.get_authors_by_ids(GetAuthorsByIdsArgs.new(param1: []))
    both = @query_sql.get_authors_by_ids_and_names(GetAuthorsByIdsAndNamesArgs.new(param1: ids, param2: %w[b c x]))
    assert_equal %w[b c], both.map(&:name).sort
  end

  # ---- :copyfrom -------------------------------------------------------------------------------------------------

  def test_copyfrom
    rows = [
      CopyAuthorsArgs.new(name: 'plain', bio: 'bio'),
      CopyAuthorsArgs.new(name: 'no bio', bio: nil),
      CopyAuthorsArgs.new(name: "tab\there, \"quotes\", back\\slash\nnewline", bio: 'special')
    ]
    @query_sql.copy_authors(rows)
    stored = @query_sql.list_authors.to_h { |a| [a.name, a.bio] }
    assert_equal rows.to_h { |r| [r.name, r.bio] }, stored
  end

  def test_copyfrom_many_rows_and_none
    @query_sql.copy_authors([])
    assert_empty @query_sql.list_authors
    @query_sql.copy_authors((1..2500).map { |i| CopyAuthorsArgs.new(name: "author #{i}", bio: nil) })
    assert_equal 2500, @query_sql.list_authors.size
  end

  # ---- sqlc.embed ------------------------------------------------------------------------------------------------

  def test_embed
    first = create_author('a', 'bio a')
    second = create_author('b')
    @query_sql.create_book(CreateBookArgs.new(name: 'book 1', author_id: first))
    @query_sql.create_book(CreateBookArgs.new(name: 'book 2', author_id: second))

    rows = @query_sql.list_all_authors_books
    assert_equal %w[a b], rows.map { |r| r.author.name }
    assert_equal ['book 1', 'book 2'], rows.map { |r| r.book.name }
    assert_instance_of Author, rows.first.author
    assert_instance_of Book, rows.first.book
    assert_equal Author.new(first, 'a', 'bio a'), rows.first.author
    assert_equal first, rows.first.book.author_id
  end

  def test_embed_with_plain_columns
    id = create_author('a', 'bio')
    @query_sql.create_book(CreateBookArgs.new(name: 'the book', author_id: id))
    row = @query_sql.get_authors_by_book_name(GetAuthorsByBookNameArgs.new(name: 'the book')).first
    assert_equal [id, 'a', 'bio'], [row.id, row.name, row.bio]
    assert_equal 'the book', row.book.name
  end

  def test_same_table_embedded_twice
    low = create_author('same')
    high = create_author('same')
    create_author('different')
    rows = @query_sql.get_duplicate_authors
    assert_equal 1, rows.size
    assert_equal [low, high], [rows.first.author.id, rows.first.author2.id]
  end

  # ---- enums -----------------------------------------------------------------------------------------------------

  def test_enum_column
    @query_sql.create_extended_bio(CreateExtendedBioArgs.new(author_name: 'a', name: 'n1', bio_type: ExtendedBioType::MEMOIR))
    @query_sql.create_extended_bio(CreateExtendedBioArgs.new(author_name: 'a', name: 'n2', bio_type: ExtendedBioType::BIOGRAPHY))
    row = @query_sql.get_first_extended_bio_by_type(GetFirstExtendedBioByTypeArgs.new(bio_type: 'Biography'))
    assert_equal GetFirstExtendedBioByTypeRow.new('a', 'n2', 'Biography'), row
    assert_equal %w[Autobiography Biography Memoir], ExtendedBioType::ALL
  end

  def test_enum_rejects_unknown_values
    assert_raises(PG::InvalidTextRepresentation) do
      @query_sql.create_extended_bio(CreateExtendedBioArgs.new(author_name: 'a', name: 'n', bio_type: 'Fiction'))
    end
  end

  # ---- transactions ----------------------------------------------------------------------------------------------

  def test_transaction_commits_and_returns_the_block_value
    result = @query_sql.transaction do |tx|
      id = tx.create_author_return_id(CreateAuthorReturnIdArgs.new(name: 'in tx', bio: nil))
      tx.create_book(CreateBookArgs.new(name: 'book', author_id: id))
      :done
    end
    assert_equal :done, result
    assert_equal ['in tx'], @query_sql.list_authors.map(&:name)
  end

  def test_transaction_rolls_back_on_error
    assert_raises(RuntimeError) do
      @query_sql.transaction do |tx|
        tx.create_author_return_id(CreateAuthorReturnIdArgs.new(name: 'rolled back', bio: nil))
        raise 'boom'
      end
    end
    assert_empty @query_sql.list_authors
  end

  def test_transaction_is_isolated_until_commit
    other = QuerySql.new({}, { 'dbname' => ENV['DB_NAME'], 'host' => ENV['POSTGRES_HOST'], 'port' => ENV['POSTGRES_PORT'],
                               'user' => ENV['DB_USER'], 'password' => ENV['DB_PASS'] }.compact)
    @query_sql.transaction do |tx|
      tx.create_author_return_id(CreateAuthorReturnIdArgs.new(name: 'uncommitted', bio: nil))
      assert_empty other.list_authors
    end
    assert_equal ['uncommitted'], other.list_authors.map(&:name)
  end

  # ---- more data types -------------------------------------------------------------------------------------------

  def test_extra_types_round_trip
    uuid = '0e52082f-bf69-480e-aff0-1a85139a1074'
    time = Time.utc(2024, 5, 6, 7, 8, 9)
    @query_sql.insert_extra_types(InsertExtraTypesArgs.new(
      c_uuid: uuid, c_jsonb: { 'a' => [1, 2, { 'b' => nil }] }.to_json, c_text_array: ['x', nil, 'y z'],
      c_integer_array: [1, 2, 3], c_timestamptz: time, c_inet: '10.1.2.3', c_money: '12.50', c_not_null: 'nn'
    ))
    row = @query_sql.get_extra_types
    assert_equal uuid, row.c_uuid
    assert_equal({ 'a' => [1, 2, { 'b' => nil }] }, row.c_jsonb)
    assert_equal ['x', nil, 'y z'], row.c_text_array
    assert_equal [1, 2, 3], row.c_integer_array
    assert_equal time, row.c_timestamptz.utc
    assert_equal IPAddr.new('10.1.2.3'), row.c_inet
    assert_includes row.c_money, '12.50'
    assert_equal 'nn', row.c_not_null
  end

  def test_extra_types_nulls
    @query_sql.insert_extra_types(InsertExtraTypesArgs.new(
      c_uuid: nil, c_jsonb: nil, c_text_array: nil, c_integer_array: nil, c_timestamptz: nil, c_inet: nil,
      c_money: nil, c_not_null: 'x'
    ))
    row = @query_sql.get_extra_types
    assert_equal [nil] * 7, row.to_h.values_at(:c_uuid, :c_jsonb, :c_text_array, :c_integer_array, :c_timestamptz,
                                              :c_inet, :c_money)
  end

  def raw_client
    PG.connect(dbname: ENV['DB_NAME'], host: ENV['POSTGRES_HOST'], port: ENV['POSTGRES_PORT'], user: ENV['DB_USER'],
               password: ENV['DB_PASS'])
  end

  def test_declared_types_match_runtime_values
    client = raw_client
    client.exec('DELETE FROM node_postgres_types')
    client.exec(<<~SQL)
      INSERT INTO node_postgres_types VALUES (B'1', 2, true, 4, 5, 6, 1.5, 2.5, 1.25, 2.25, '2024-01-02', '03:04:05',
        '2024-01-02 03:04:05', 'a', 'b', '\\x0102', 'c', '{"a": 1}')
    SQL
    row = @query_sql.test
    assert_empty RbsTypes.mismatches(row, File.expand_path('../examples/pg/query_sql.rbs', __dir__), 'TestRow')
    assert_equal Date.new(2024, 1, 2), row.c_date
    assert_equal BigDecimal('1.5'), row.c_decimal
    assert_equal({ 'a' => 1 }, row.c_json)
    assert_equal "\x01\x02".b, row.c_bytea.b
  ensure
    client&.exec('DELETE FROM node_postgres_types')
  end

  def test_declared_types_match_runtime_values_for_nulls
    client = raw_client
    client.exec('DELETE FROM node_postgres_types')
    client.exec('INSERT INTO node_postgres_types (c_integer) VALUES (NULL)')
    row = @query_sql.test
    assert_empty RbsTypes.mismatches(row, File.expand_path('../examples/pg/query_sql.rbs', __dir__), 'TestRow')
    assert_equal [nil], row.to_h.except(:c_serial).values.uniq # c_serial is filled by its default
  ensure
    client&.exec('DELETE FROM node_postgres_types')
  end

  def test_extra_types_match_declared_types
    @query_sql.insert_extra_types(InsertExtraTypesArgs.new(
      c_uuid: SecureRandom.uuid, c_jsonb: '[1]', c_text_array: %w[a], c_integer_array: [1], c_timestamptz: Time.now,
      c_inet: '::1', c_money: '1', c_not_null: 'x'
    ))
    assert_empty RbsTypes.mismatches(@query_sql.get_extra_types, File.expand_path('../examples/pg/query_sql.rbs', __dir__),
                                     'GetExtraTypesRow')
  end

  # ---- models ----------------------------------------------------------------------------------------------------

  def test_models_are_generated_for_every_table
    assert_equal %i[id name bio], Author.members
    assert_equal %i[id name author_id description], Book.members
    assert_equal %i[author_name name bio_type], ExtendedBio.members
  end
end
