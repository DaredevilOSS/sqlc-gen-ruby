#!/usr/bin/env ruby
gem 'minitest'     # ensures using the gem, and not the built-in MT
require 'minitest/autorun'
require 'logger'
require 'stringio'
require 'sqlite3'
require_relative 'consts'
require_relative 'rbs_types'
require_relative '../examples/sqlite3/query_sql'

# End-to-end tests of the code generated for examples/authors/sqlite, against a real (in-memory) SQLite database.
class TestSqlite3 < Minitest::Test
  include Sqlite3Codegen

  SCHEMA = File.read(File.expand_path('../examples/authors/sqlite/schema.sql', __dir__))

  def setup
    @db = SQLite3::Database.new(':memory:')
    @db.execute_batch(SCHEMA)
    @query_sql = QuerySql.new(@db)
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

    @query_sql.delete_author(id: first)
    assert_equal [Consts::DR_SEUSS_AUTHOR], @query_sql.list_authors.map(&:name)
  end

  def test_nullable_columns_round_trip_nil
    id = create_author('no bio', nil)
    assert_nil @query_sql.get_author(id: id).bio
  end

  # ---- :execlastid / :execrows -----------------------------------------------------------------------------------

  def test_execlastid_returns_the_returning_column
    first = create_author('a')
    second = create_author('b')
    assert_kind_of Integer, first
    assert_equal first + 1, second
    assert_kind_of Integer, @query_sql.create_book(name: 'book', author_id: first)
  end

  def test_execresult_returns_rows_affected_and_last_id
    result = @query_sql.create_author_result(name: 'a', bio: nil)
    assert_equal 1, result.rows_affected
    assert_equal result.last_insert_id, @query_sql.list_authors.first.id
  end

  def test_batch_commands_run_once_per_args
    @query_sql.create_authors_batch([CreateAuthorsBatchArgs.new('a', nil), CreateAuthorsBatchArgs.new('b', 'x'),
                                     CreateAuthorsBatchArgs.new('b', 'y')])
    ids = @query_sql.list_authors.to_h { |a| [a.bio, a.id] }
    found = @query_sql.get_author_batch([GetAuthorBatchArgs.new(ids['x']), GetAuthorBatchArgs.new(-1)])
    assert_equal ['b', nil], found.map { |r| r&.name }
    many = @query_sql.list_authors_by_name_batch(%w[b a c].map { |n| ListAuthorsByNameBatchArgs.new(n) })
    assert_equal [%w[x y], [nil], []], many.map { |rows| rows.map(&:bio) }
    assert_nil @query_sql.create_authors_batch([])
  end

  def test_declared_types_with_parameters
    uid = '6f1c4a52-1d2b-4c3e-9f00-0a1b2c3d4e5f'
    @query_sql.insert_declared_types(c_varchar: 'v', c_decimal: 1.5, c_unsigned_big_int: 7, c_native: 'n', c_double: 2.5,
                                     c_json: '{"a":[1]}', c_uuid: uid)
    row = @query_sql.get_declared_types
    assert_equal ['v', 1.5, 7, 'n', 2.5, '{"a":[1]}', uid], row.to_h.values
    assert_empty RbsTypes.mismatches(row, File.expand_path('../examples/sqlite3/query_sql.rbs', __dir__), 'GetDeclaredTypesRow')
  end

  def test_execrows_returns_affected_row_count
    create_author('with bio', 'bio')
    create_author('with bio 2', 'bio')
    create_author('without bio', nil)
    assert_equal 2, @query_sql.update_author_bios(bio: 'new bio')
  end

  # ---- sqlc.arg / sqlc.narg --------------------------------------------------------------------------------------

  def test_numbered_parameters_limit_and_offset
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
  end

  def test_empty_slice_matches_nothing
    create_author('a')
    assert_empty @query_sql.get_authors_by_ids(ids: [])
  end

  def test_several_slices_in_one_query
    ids = %w[a b c].map { |name| create_author(name) }
    got = @query_sql.get_authors_by_ids_and_names(ids: ids, names: %w[b c x])
    assert_equal %w[b c], got.map(&:name).sort
  end

  # ---- :copyfrom -------------------------------------------------------------------------------------------------

  def test_copyfrom
    rows = [
      CopyAuthorsArgs.new(name: 'plain', bio: 'bio'),
      CopyAuthorsArgs.new(name: 'no bio', bio: nil),
      CopyAuthorsArgs.new(name: "comma, 'quotes', \"double\", back\\slash\nnewline", bio: 'special')
    ]
    @query_sql.copy_authors(rows)
    assert_equal rows.to_h { |r| [r.name, r.bio] }, @query_sql.list_authors.to_h { |a| [a.name, a.bio] }
  end

  def test_copyfrom_is_batched_below_the_bound_parameter_limit
    @query_sql.copy_authors([])
    assert_empty @query_sql.list_authors
    @query_sql.copy_authors((1..2500).map { |i| CopyAuthorsArgs.new(name: "author #{i}", bio: i.to_s) })
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

  def test_declared_types_match_runtime_values
    @db.execute('INSERT INTO authors (id, name, bio) VALUES (1, ?, ?)', ['a', 'b'])
    @db.execute('INSERT INTO authors (id, name, bio) VALUES (2, ?, NULL)', ['c'])
    rbs = File.expand_path('../examples/sqlite3/query_sql.rbs', __dir__)
    @query_sql.list_authors.each { |row| assert_empty RbsTypes.mismatches(row, rbs, 'ListAuthorsRow') }
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

  def test_transaction_mode
    assert_equal 1, @query_sql.transaction(mode: :immediate) { 1 }
  end

  # ---- Ruby conventions: bang finders, logger ----------------------------------------------------------------

  def test_bang_finder_raises_not_found
    id = create_author('a', nil)
    assert_equal 'a', @query_sql.get_author!(id: id).name
    error = assert_raises(QuerySql::NotFound) { @query_sql.get_author!(id: -1) }
    assert_equal 'GetAuthor returned no row', error.message
    assert_nil @query_sql.get_author(id: -1) # the plain finder still returns nil
  end

  def test_logger_receives_query_names_and_durations
    io = StringIO.new
    logged = QuerySql.new(@db, logger: Logger.new(io, level: Logger::DEBUG))
    logged.list_authors
    logged.transaction { |tx| tx.list_authors }
    assert_match(/QuerySql#list_authors \(\d+\.\dms\)/, io.string)
    assert_match(/QuerySql#transaction \(\d+\.\dms\)/, io.string)
    @query_sql.list_authors # no logger: nothing is logged, nothing breaks
  end

  # ---- models ----------------------------------------------------------------------------------------------------

  def test_models_are_generated_for_every_table
    assert_equal %i[id name bio], Author.members
    assert_equal %i[id name author_id description], Book.members
  end

  # ---- regressions -----------------------------------------------------------------------------------------------

  def test_exec_and_execrows_with_returning_run_to_the_end
    @query_sql.create_regression(order: 'a', price: 1.5)
    @query_sql.create_regression(order: 'b', price: nil)
    assert_equal 2, @query_sql.update_regression_prices(price: 2.25)
    assert_equal [['a', 2.25], ['b', 2.25]], @query_sql.list_regressions.map { |r| [r.order, r.price] }
  end

  def test_copyfrom_quotes_reserved_column_names_and_untyped_expressions
    assert_equal 0, @query_sql.get_max_regression_price!.max_price
    @query_sql.copy_regressions([CopyRegressionsArgs.new(order: 'x', price: 3.5)])
    assert_equal [['x', 3.5]], @query_sql.list_regressions.map { |r| [r.order, r.price] }
    assert_in_delta 3.5, @query_sql.get_max_regression_price!.max_price
  end

  def test_copyfrom_is_all_or_nothing
    rows = (1..3000).map { |i| CopyRegressionsArgs.new(order: i == 2900 ? nil : "o#{i}", price: i) }
    assert_raises(SQLite3::ConstraintException) { @query_sql.copy_regressions(rows) }
    assert_empty @query_sql.list_regressions
  end

  def test_failed_copyfrom_in_a_transaction_rolls_back_only_itself
    @query_sql.transaction do |tx|
      tx.create_author_return_id(name: 'kept', bio: nil)
      bad = [CopyRegressionsArgs.new(order: 'a', price: 1), CopyRegressionsArgs.new(order: nil, price: 2)]
      assert_raises(SQLite3::ConstraintException) { tx.copy_regressions(bad) }
    end
    assert_equal ['kept'], @query_sql.list_authors.map(&:name)
    assert_empty @query_sql.list_regressions
  end

  def test_threads_sharing_a_database_take_turns_in_transactions
    other = QuerySql.new(@db)
    threads = Array.new(8) do |i|
      Thread.new do
        20.times do |j|
          (i.even? ? @query_sql : other).transaction do |tx|
            tx.transaction { tx.create_author_return_id(name: "t#{i}-#{j}", bio: nil) }
          end
        end
      end
    end
    threads.each(&:join)
    assert_equal 160, @query_sql.list_authors.size
  end

  def test_unknown_transaction_mode_is_rejected_before_beginning
    assert_raises(ArgumentError) { @query_sql.transaction(mode: :bogus) { flunk } }
    refute_predicate @db, :transaction_active?
  end

  def test_transaction_left_with_break_or_throw_commits
    2.times do |i|
      @query_sql.transaction do |tx|
        tx.create_author_return_id(name: "break #{i}", bio: nil)
        break
      end
    end
    catch(:out) do
      @query_sql.transaction do |tx|
        tx.create_author_return_id(name: 'throw', bio: nil)
        throw :out
      end
    end
    refute @db.transaction_active?
    assert_equal ['break 0', 'break 1', 'throw'], @query_sql.list_authors.map(&:name).sort
  end
end
