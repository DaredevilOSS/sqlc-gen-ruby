#!/usr/bin/env ruby
gem 'minitest'     # ensures using the gem, and not the built-in MT
require 'minitest/autorun'
require 'async'
require 'async/barrier'
require_relative 'consts'
require_relative 'rbs_types'
require_relative '../examples/mysql2/query_sql'

# End-to-end tests of the code generated for examples/authors/mysql, against a real MySQL / MariaDB server.
class TestMysql2 < Minitest::Test
  include Mysql2Codegen

  def mysql2_params
    {
      'database' => ENV['DB_NAME'],
      'host' => ENV['MYSQL_HOST'],
      'port' => ENV['MYSQL_PORT']&.to_i, # optional
      'username' => ENV['DB_USER'],
      'local_infile' => true # required by :copyfrom (LOAD DATA LOCAL INFILE)
    }.compact
  end

  def setup
    @query_sql = QuerySql.connect(mysql2_params)
    @query_sql.truncate_authors # cascades to books
    @query_sql.truncate_extended_bios
  end

  def create_author(name, bio = nil)
    @query_sql.create_author_return_id(name: name, bio: bio)
  end

  # ---- :one / :many / :exec -------------------------------------------------------------------------------------

  def test_flow
    first = create_author(Consts::BOJACK_AUTHOR, Consts::BOJACK_THEME)
    @query_sql.create_author(name: Consts::DR_SEUSS_AUTHOR, bio: Consts::DR_SEUSS_QUOTE)

    assert_equal GetAuthorRow.new(first, Consts::BOJACK_AUTHOR, Consts::BOJACK_THEME),
                 @query_sql.get_author(id: first)
    assert_nil @query_sql.get_author(id: -1)
    assert_equal [Consts::BOJACK_AUTHOR, Consts::DR_SEUSS_AUTHOR].sort, @query_sql.list_authors.map(&:name).sort

    @query_sql.update_author(bio: Consts::DR_SEUSS_NEW_QUOTE, id: first)
    assert_equal Consts::DR_SEUSS_NEW_QUOTE, @query_sql.get_author(id: first).bio

    @query_sql.delete_author(id: first)
    assert_equal [Consts::DR_SEUSS_AUTHOR], @query_sql.list_authors.map(&:name)
  end

  def test_nullable_columns_round_trip_nil
    id = create_author('no bio', nil)
    assert_nil @query_sql.get_author(id: id).bio
  end

  def test_one_on_empty_table_returns_nil
    assert_nil @query_sql.test
  end

  def test_prepared_statements_are_closed
    id = create_author('a')
    300.times { @query_sql.get_author(id: id) }
    status = Mysql2::Client.new(mysql2_params).query("SHOW GLOBAL STATUS LIKE 'Prepared_stmt_count'").first
    assert_equal '0', status['Value'].to_s, 'prepared statements leak on the server'
  end

  # ---- :execlastid / :execrows -----------------------------------------------------------------------------------

  def test_execlastid_returns_the_new_id
    first = create_author('a')
    second = create_author('b')
    assert_kind_of Integer, first
    assert_equal first + 1, second
    assert_kind_of Integer, @query_sql.create_book(name: 'book', author_id: first)
  end

  def test_execrows_returns_affected_row_count
    create_author('with bio', 'bio')
    create_author('with bio 2', 'bio')
    create_author('without bio', nil)
    assert_equal 2, @query_sql.update_author_bios(bio: 'new bio')
  end

  # ---- sqlc.arg / sqlc.narg --------------------------------------------------------------------------------------

  def test_positional_args_limit_and_offset
    %w[a b c d].each { |name| create_author(name) }
    page = @query_sql.list_authors_paged(limit: 2, offset: 1)
    assert_equal %w[b c], page.map(&:name)
  end

  def test_nullable_named_arg
    %w[abc abd xyz].each { |name| create_author(name) }
    assert_equal 3, @query_sql.get_author_by_name_pattern(name_pattern: nil).size
    ab = @query_sql.get_author_by_name_pattern(name_pattern: 'ab%')
    assert_equal %w[abc abd], ab.map(&:name).sort
  end

  # ---- sqlc.slice ------------------------------------------------------------------------------------------------

  def test_slice
    ids = %w[a b c].map { |name| create_author(name) }
    got = @query_sql.get_authors_by_ids(ids: ids.first(2))
    assert_equal ids.first(2).sort, got.map(&:id).sort
    assert_equal [ids.last], @query_sql.get_authors_by_ids(ids: [ids.last]).map(&:id)
  end

  def test_empty_slice_matches_nothing
    create_author('a')
    assert_empty @query_sql.get_authors_by_ids(ids: [])
  end

  def test_several_slices_in_one_query
    ids = %w[a b c].map { |name| create_author(name) }
    got = @query_sql.get_authors_by_ids_and_names(ids: ids, names: %w[b c x])
    assert_equal %w[b c], got.map(&:name).sort
    assert_empty @query_sql.get_authors_by_ids_and_names(ids: ids, names: [])
  end

  # ---- :copyfrom -------------------------------------------------------------------------------------------------

  def test_copyfrom
    rows = [
      CopyAuthorsArgs.new(name: 'plain', bio: 'bio'),
      CopyAuthorsArgs.new(name: 'no bio', bio: nil),
      CopyAuthorsArgs.new(name: "comma, \"quotes\", back\\slash\nnewline", bio: 'special'),
      CopyAuthorsArgs.new(name: '\N', bio: 'a literal \N is not NULL')
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
    @query_sql.create_book(name: 'book 1', author_id: first)
    @query_sql.create_book(name: 'book 2', author_id: second)

    rows = @query_sql.list_all_authors_books
    assert_equal %w[a b], rows.map { |r| r.author.name }
    assert_equal ['book 1', 'book 2'], rows.map { |r| r.book.name }
    assert_equal Author.new(first, 'a', 'bio a'), rows.first.author
    assert_instance_of Book, rows.first.book
    assert_equal first, rows.first.book.author_id
  end

  def test_embed_with_plain_columns
    id = create_author('a', 'bio')
    @query_sql.create_book(name: 'the book', author_id: id)
    row = @query_sql.get_authors_by_book_name(name: 'the book').first
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

  # ---- enums / sets ----------------------------------------------------------------------------------------------

  def test_enum_and_set_columns
    @query_sql.create_extended_bio(author_name: 'a', name: 'n1', bio_type: ExtendedBiosBioType::MEMOIR,
                                                            author_type: 'Author,Editor')
    @query_sql.create_extended_bio(author_name: 'a', name: 'n2', bio_type: 'Biography', author_type: nil)
    row = @query_sql.get_first_extended_bio_by_type(bio_type: 'Memoir')
    assert_equal GetFirstExtendedBioByTypeRow.new('a', 'n1', 'Memoir', 'Author,Editor'), row
    assert_equal %w[Autobiography Biography Memoir], ExtendedBiosBioType::ALL
    assert_equal %w[Author Editor Translator], ExtendedBiosAuthorType::ALL
  end

  # ---- transactions ----------------------------------------------------------------------------------------------

  def test_transaction_commits_and_returns_the_block_value
    result = @query_sql.transaction do |tx|
      id = tx.create_author_return_id(name: 'in tx', bio: nil)
      tx.create_book(name: 'book', author_id: id)
      :done
    end
    assert_equal :done, result
    assert_equal ['in tx'], @query_sql.list_authors.map(&:name)
  end

  def test_transaction_rolls_back_on_error
    assert_raises(RuntimeError) do
      @query_sql.transaction do |tx|
        tx.create_author_return_id(name: 'rolled back', bio: nil)
        raise 'boom'
      end
    end
    assert_empty @query_sql.list_authors
  end

  def test_transaction_is_isolated_until_commit
    other = QuerySql.connect(mysql2_params)
    @query_sql.transaction do |tx|
      tx.create_author_return_id(name: 'uncommitted', bio: nil)
      assert_empty other.list_authors
    end
    assert_equal ['uncommitted'], other.list_authors.map(&:name)
  end

  def test_declared_types_match_runtime_values
    client = Mysql2::Client.new(mysql2_params)
    client.query('DELETE FROM node_mysql_types')
    client.query(<<~SQL)
      INSERT INTO node_mysql_types VALUES (b'1', 1, 1, 0, 2, 3, 4, 5, 6, 7, 1.5, 2.5, 3.5, 4.5, 1.25, 2.25, 3.25,
        '2024-01-02', '03:04:05', '2024-01-02 03:04:05', '2024-01-02 03:04:05', 2024, 'a', 'b', 'c', 'dd', 'x', 'yy',
        'tb', 'tt', 'bl', 'te', 'mb', 'mt', 'lb', 'lt', '{"a": 1}')
    SQL
    row = @query_sql.test
    assert_empty RbsTypes.mismatches(row, File.expand_path('../examples/mysql2/query_sql.rbs', __dir__), 'TestRow')
    assert_equal Date.new(2024, 1, 2), row.c_date
    assert_equal BigDecimal('1.5'), row.c_decimal
    assert_equal 2024, row.c_year
  ensure
    client&.query('DELETE FROM node_mysql_types')
  end

  def test_declared_types_match_runtime_values_for_nulls
    client = Mysql2::Client.new(mysql2_params)
    client.query('DELETE FROM node_mysql_types')
    client.query('INSERT INTO node_mysql_types (c_int) VALUES (NULL)')
    row = @query_sql.test
    assert_empty RbsTypes.mismatches(row, File.expand_path('../examples/mysql2/query_sql.rbs', __dir__), 'TestRow')
  ensure
    client&.query('DELETE FROM node_mysql_types')
  end

  def test_nested_transaction_rolls_back_to_a_savepoint
    @query_sql.transaction do |tx|
      tx.create_author_return_id(name: 'outer', bio: nil)
      assert_raises(RuntimeError) do
        tx.transaction do |inner|
          inner.create_author_return_id(name: 'inner, rolled back', bio: nil)
          raise 'boom'
        end
      end
      tx.create_author_return_id(name: 'outer 2', bio: nil)
    end
    assert_equal ['outer', 'outer 2'], @query_sql.list_authors.map(&:name).sort
  end

  def test_nested_transaction_commits_with_the_outer_one
    @query_sql.transaction do |tx|
      assert_equal 7, tx.transaction { |inner| inner.create_author_return_id(name: 'inner', bio: nil) && 7 }
    end
    assert_equal ['inner'], @query_sql.list_authors.map(&:name)
    assert_raises(RuntimeError) do
      @query_sql.transaction do |tx|
        tx.transaction { |inner| inner.create_author_return_id(name: 'inner 2', bio: nil) }
        raise 'boom'
      end
    end
    assert_equal ['inner'], @query_sql.list_authors.map(&:name)
  end

  def test_missing_keyword_arguments_are_errors
    assert_raises(ArgumentError) { @query_sql.get_author }
    assert_raises(ArgumentError) { @query_sql.get_author(id: 1, unknown: 2) }
  end

  def test_named_nullable_arguments_are_optional
    create_author('abc')
    assert_equal ['abc'], @query_sql.get_author_by_name_pattern.map(&:name)
  end

  def test_transaction_isolation_level_is_accepted
    assert_equal 1, @query_sql.transaction(isolation: :serializable) { 1 }
    assert_raises(KeyError) { @query_sql.transaction(isolation: :bogus) { nil } }
  end

  def test_queries_can_share_an_injected_pool
    pool = ConnectionPool.new(size: 2) { Mysql2::Client.new(**mysql2_params.transform_keys(&:to_sym)) }
    first = QuerySql.new(pool)
    second = QuerySql.new(pool)
    id = first.create_author_return_id(name: 'shared', bio: nil)
    assert_equal 'shared', second.get_author(id: id).name
  end

  # The generated classes are plain synchronous Ruby; under the Fiber scheduler (the `async` gem) the pooled
  # queries overlap because mysql2 and connection_pool are fiber aware.
  def test_queries_run_concurrently_under_the_fiber_scheduler
    queries = QuerySql.connect(mysql2_params, size: 5)
    pool = queries.instance_variable_get(:@db)
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    Sync do
      barrier = Async::Barrier.new
      5.times { barrier.async { pool.with { |client| client.query('select sleep(0.4)') } } }
      barrier.wait
    end
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
    assert_operator elapsed, :<, 1.5, "5 x 0.4s queries took #{elapsed}s: they ran one after the other"

    names = Sync do
      barrier = Async::Barrier.new
      tasks = Array.new(10) { |i| barrier.async { queries.create_author_return_id(name: "fiber #{i}", bio: nil) } }
      barrier.wait
      tasks.map(&:wait)
    end
    assert_equal 10, names.uniq.size
    assert_equal 10, @query_sql.list_authors.size
  end

  # ---- models ----------------------------------------------------------------------------------------------------

  def test_models_are_generated_for_every_table
    assert_equal %i[id name bio], Author.members
    assert_equal %i[id name author_id description], Book.members
    assert_equal %i[author_name name bio_type author_type], ExtendedBio.members
  end
end
