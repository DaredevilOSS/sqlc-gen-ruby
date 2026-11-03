#!/usr/bin/env ruby
gem 'minitest'     # ensures using the gem, and not the built-in MT
require 'minitest/autorun'
require 'logger'
require 'stringio'
require 'sqlite3'
require 'timeout'
require 'async'
require 'async/barrier'
require 'tempfile'
EXAMPLES_DIR = File.expand_path(ENV.fetch('EXAMPLES_DIR', File.expand_path('../examples', __dir__))).freeze
require_relative 'consts'
require_relative 'rbs_types'
require File.join(EXAMPLES_DIR, 'sqlite3/query_sql')
RbsTypes.install(Object.const_get("#{ENV.fetch('EXAMPLES_MODULE', 'Sqlite3Codegen')}::QuerySql"),
                 File.join(EXAMPLES_DIR, 'sqlite3/query_sql.rbs'))

# End-to-end tests of the code generated for examples/authors/sqlite, against a real (in-memory) SQLite database.
class TestSqlite3 < Minitest::Test
  include Object.const_get(ENV.fetch('EXAMPLES_MODULE', 'Sqlite3Codegen'))

  TEXT_PARTS = ["é", '🙂', "\t", "\n", "\r", '\\', "'", '"', ',', '\N', 'NULL'].freeze

  def row_for(klass, values)
    klass.new(**klass.members.zip(values).to_h)
  end

  def assert_row_layout(row)
    if defined?(Data) && row.is_a?(Data)
      assert_predicate row, :frozen?
      assert_equal row.to_h, row.with.to_h
    else
      assert_kind_of Struct, row
      assert row.class.keyword_init?
      refute_predicate row, :frozen?
    end
    case row
    in { id:, name: }
      assert_kind_of Integer, id
      assert_equal row.name, name
    else
      flunk 'row did not support keyword pattern matching'
    end
  end

  def seeded_random
    seed = Integer(ENV.fetch('SEED', '1793729686'))
    warn "SEED=#{seed} #{self.class}"
    Random.new(seed)
  end

  def random_text(random)
    Array.new(random.rand(1..8)) { TEXT_PARTS.fetch(random.rand(TEXT_PARTS.length)) }.join
  end

  def old_timeout_version?
    defined?(::Timeout::VERSION) && (::Timeout::VERSION.split('.').map(&:to_i) <=> [0, 4]).negative?
  end

  def return_from_transaction(name)
    @query_sql.transaction do |tx|
      tx.create_author_return_id(name: name, bio: nil)
      return :returned
    end
  end

  SCHEMA = File.read(File.expand_path('../examples/authors/sqlite/schema.sql', __dir__))

  def setup
    @db = SQLite3::Database.new(':memory:')
    @db.execute_batch(SCHEMA)
    @db.create_function('sleep', 1) { |_func, seconds| Kernel.sleep(seconds) }
    @query_sql = QuerySql.new(@db)
  end

  # Close on the test's own thread: a database left to the GC can be finalized on another thread while a timed-out
  # `sleep` function still holds its SQLite mutex, which deadlocks the process (seen on Ruby 3.1 / sqlite3 2.8).
  def teardown
    @db.close
  end

  def create_author(name, bio = nil)
    @query_sql.create_author_return_id(name: name, bio: bio)
  end

  # ---- :one / :many / :exec -------------------------------------------------------------------------------------

  def test_flow
    first = create_author(Consts::BOJACK_AUTHOR, Consts::BOJACK_THEME)
    @query_sql.create_author(name: Consts::DR_SEUSS_AUTHOR, bio: Consts::DR_SEUSS_QUOTE)

    assert_equal row_for(GetAuthorRow, [first, Consts::BOJACK_AUTHOR, Consts::BOJACK_THEME]),
                 @query_sql.get_author(id: first)
    assert_nil @query_sql.get_author(id: -1)
    assert_equal [Consts::BOJACK_AUTHOR, Consts::DR_SEUSS_AUTHOR].sort, @query_sql.list_authors.map(&:name).sort

    @query_sql.delete_author(id: first)
    assert_equal [Consts::DR_SEUSS_AUTHOR], @query_sql.list_authors.map(&:name)
  end

  def test_rows_and_embedded_models_have_supported_layout_and_pattern_matching
    first = create_author('pattern')
    create_author('pattern')
    assert_row_layout(@query_sql.get_author(id: first))
    embedded = @query_sql.get_duplicate_authors.first.author
    assert_row_layout(embedded)
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
    @query_sql.create_authors_batch([CreateAuthorsBatchArgs.new(name: 'a', bio: nil), CreateAuthorsBatchArgs.new(name: 'b', bio: 'x'),
                                     CreateAuthorsBatchArgs.new(name: 'b', bio: 'y')])
    ids = @query_sql.list_authors.to_h { |a| [a.bio, a.id] }
    found = @query_sql.get_author_batch([GetAuthorBatchArgs.new(id: ids['x']), GetAuthorBatchArgs.new(id: -1)])
    assert_equal ['b', nil], found.map { |r| r&.name }
    many = @query_sql.list_authors_by_name_batch(%w[b a c].map { |n| ListAuthorsByNameBatchArgs.new(name: n) })
    assert_equal [%w[x y], [nil], []], many.map { |rows| rows.map(&:bio) }
    assert_nil @query_sql.create_authors_batch([])
  end

  def test_batches_are_not_atomic_without_a_transaction
    rows = [CreateAuthorsBatchArgs.new(name: 'committed', bio: nil), CreateAuthorsBatchArgs.new(name: nil, bio: nil)]
    assert_raises(SQLite3::ConstraintException) { @query_sql.create_authors_batch(rows) }
    assert_equal ['committed'], @query_sql.list_authors.map(&:name)
  end

  def test_declared_types_with_parameters
    uid = '6f1c4a52-1d2b-4c3e-9f00-0a1b2c3d4e5f'
    @query_sql.insert_declared_types(c_varchar: 'v', c_decimal: 1.5, c_unsigned_big_int: 7, c_native: 'n', c_double: 2.5,
                                     c_json: '{"a":[1]}', c_uuid: uid)
    row = @query_sql.get_declared_types
    assert_equal ['v', 1.5, 7, 'n', 2.5, '{"a":[1]}', uid], row.to_h.values
    assert_empty RbsTypes.mismatches(row, File.join(EXAMPLES_DIR, 'sqlite3/query_sql.rbs'), 'GetDeclaredTypesRow')
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

  def test_required_argument_after_optional_named_argument
    %w[alpha beta gamma].each { |name| create_author(name) }
    assert_equal %w[alpha beta gamma], @query_sql.get_authors_by_optional_name(lim: 10).map(&:name).sort
    assert_equal ['beta'], @query_sql.get_authors_by_optional_name(lim: 10, name_filter: 'beta').map(&:name)
  end

  def test_keyword_and_method_names_keep_distinct_row_and_argument_names
    args = { id: 1, class_: 'class', end_: 'end', hash: 'hash', method: 'method', count: 7,
             camel_case: 'camel', http_server: 'server' }
    @query_sql.insert_name_case(**args)
    row = @query_sql.get_name_case(**args)
    count_member = row.is_a?(Struct) ? :count_ : :count
    assert_equal %i[id class_ end hash_ method_].concat([count_member, :camelCase, :HTTPServer]), row.class.members
    assert_equal %w[class end hash method], %i[class_ end hash_ method_].map { |member| row.public_send(member) }
    assert_equal 7, row.public_send(count_member)
    assert_equal 'camel', row.public_send(:camelCase)
    assert_equal 'server', row.public_send(:HTTPServer)
    assert_equal 1, @query_sql.get_http_server(id: 1).id
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

  def test_numbered_placeholders_keep_their_bindings_after_slice_expansion
    ids = %w[slice-a slice-b slice-c slice-d slice-e].map { |name| create_author(name) }
    ids.each do |count|
      selected = ids.first(count)
      more = ids.reverse
      query = @query_sql.get_authors_by_mixed_placeholders(n: 'slice-a', ids: selected, id: 0, more: more)
      sql_ids = selected.empty? ? 'NULL' : Array.new(selected.size, '?').join(', ')
      more_sql_ids = Array.new(more.size, '?').join(', ')
      expected = @db.execute(
        "SELECT id, name, bio FROM authors WHERE name = ? AND id IN (#{sql_ids}) AND name = ? " \
        "AND id > ? AND id IN (#{more_sql_ids}) AND 'x?' != '?3' ORDER BY id",
        ['slice-a', *selected, 'slice-a', 0, *more]
      ).map { |row| row_for(GetAuthorsByMixedPlaceholdersRow, row) }
      assert_equal expected, query, "slice count #{count}"
    end
  end

  def test_non_slice_numbered_placeholders_keep_sql_order
    create_author('bob')
    create_author('filler')
    create_author('alice')

    sql = 'SELECT id, name, bio FROM authors WHERE name = ? AND name != ? AND id > ? AND name = ? ORDER BY id'
    expected = @db.execute(sql, ['alice', 'bob', 1, 'alice'])
                   .map { |row| row_for(GetAuthorsByRepeatedNamedAndPositionalRow, row) }

    assert_equal [3], expected.map(&:id)
    assert_equal expected, @query_sql.get_authors_by_repeated_named_and_positional(n: 'alice', other: 'bob', id: 1)
  end

  def test_batch_numbered_placeholders_keep_sql_order
    create_author('bob')
    create_author('filler')
    create_author('alice')
    create_author('carol')

    args = [
      GetAuthorsByRepeatedNamedAndPositionalBatchArgs.new(n: 'alice', other: 'bob', id: 1),
      GetAuthorsByRepeatedNamedAndPositionalBatchArgs.new(n: 'carol', other: 'alice', id: 1),
      GetAuthorsByRepeatedNamedAndPositionalBatchArgs.new(n: 'alice', other: 'alice', id: 0)
    ]
    sql = 'SELECT id, name, bio FROM authors WHERE name = ? AND name != ? AND id > ? AND name = ? ORDER BY id LIMIT 1'
    expected = args.map do |row|
      result = @db.execute(sql, [row.n, row.other, row.id, row.n]).first
      result && row_for(GetAuthorsByRepeatedNamedAndPositionalBatchRow, result)
    end

    assert_equal expected, @query_sql.get_authors_by_repeated_named_and_positional_batch(args)
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

  def test_copyfrom_accepts_sqlc_named_values
    rows = [
      CopyAuthorsNamedArgs.new(name: 'named one', bio: 'first bio'),
      CopyAuthorsNamedArgs.new(name: 'named two', bio: nil)
    ]

    @query_sql.copy_authors_named(rows)

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
    assert_equal row_for(Author, [first, 'a', 'bio a']), rows.first.author
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

  def test_outer_join_embed_is_nil_without_a_match
    with_book = create_author('a')
    create_author('b')
    @query_sql.create_book(name: 'book', author_id: with_book)
    rows = @query_sql.list_authors_with_optional_book
    assert_equal 'book', rows.first.book.name
    assert_equal 'b', rows.last.author.name
    assert_nil rows.last.book
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
    rbs = File.join(EXAMPLES_DIR, 'sqlite3/query_sql.rbs')
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

  def test_immediate_and_exclusive_transactions_block_a_second_connection
    Tempfile.create('sqlite-lock-test') do |file|
      first = SQLite3::Database.new(file.path)
      first.execute_batch(SCHEMA)
      second = SQLite3::Database.new(file.path)
      second.busy_timeout = 0
      query = QuerySql.new(first)
      %i[immediate exclusive].each do |mode|
        assert_raises(SQLite3::BusyException) do
          query.transaction(mode: mode) { second.execute('BEGIN IMMEDIATE') }
        end
        second.execute('ROLLBACK') if second.transaction_active?
      end
    ensure
      second&.close
      first&.close
    end
  end

  def test_fibers_sharing_a_database_take_turns
    results = Sync do
      barrier = Async::Barrier.new
      tasks = Array.new(8) do |i|
        barrier.async do
          @query_sql.transaction do |tx|
            id = tx.create_author_return_id(name: "fiber #{i}", bio: nil)
            tx.get_author(id: id).name
          end
        end
      end
      barrier.wait
      tasks.map(&:wait)
    end
    assert_equal (0...8).map { |i| "fiber #{i}" }.sort, results.sort
    assert_equal 8, @query_sql.list_authors.size
  end

  def test_a_database_returning_hash_rows_still_builds_rows
    db = SQLite3::Database.new(':memory:', results_as_hash: true)
    db.execute_batch(SCHEMA)
    queries = QuerySql.new(db)
    id = queries.create_author_return_id(name: 'hash', bio: 'rows')
    assert_kind_of Integer, id
    assert_equal row_for(GetAuthorRow, [id, 'hash', 'rows']), queries.get_author(id: id)
    queries.create_book(name: 'book', author_id: id)
    row = queries.list_all_authors_books.first
    assert_equal %w[hash book], [row.author.name, row.book.name]
    assert_equal [id], queries.get_authors_by_repeated_named_and_positional_batch(
      [GetAuthorsByRepeatedNamedAndPositionalBatchArgs.new(n: 'hash', other: 'x', id: 0)]
    ).map { |r| r&.id }
    assert_equal [{ 'id' => id, 'name' => 'hash' }], db.execute('SELECT id, name FROM authors') # setting left alone
  ensure
    db&.close
  end

  # ---- Ruby conventions: bang finders, logger ----------------------------------------------------------------

  def test_bang_finder_raises_not_found
    id = create_author('a', nil)
    assert_equal 'a', @query_sql.get_author!(id: id).name
    error = assert_raises(QuerySql::NotFound) { @query_sql.get_author!(id: -1) }
    assert_equal 'GetAuthor returned no row', error.message
    assert_nil @query_sql.get_author(id: -1) # the plain finder still returns nil
  end

  def test_every_one_query_has_a_bang_method
    methods = File.read(File.join(EXAMPLES_DIR, 'sqlite3/query_sql.rbs')).scan(/^\s+def (\w+):.* -> \w+Row\?$/).flatten
    refute_empty methods
    methods.each { |name| assert_respond_to @query_sql, "#{name}!" }
  end

  def test_logger_receives_query_names_and_durations
    io = StringIO.new
    logged = QuerySql.new(@db, logger: Logger.new(io, level: Logger::DEBUG))
    logged.get_author(id: -987654321)
    logged.transaction { |tx| tx.list_authors }
    assert_match(/DEBUG -- .*QuerySql#get_author \(\d+\.\dms\)/, io.string)
    assert_match(/DEBUG -- .*QuerySql#transaction \(\d+\.\dms\)/, io.string)
    refute_includes io.string, '-987654321'
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
    expected = old_timeout_version? ? [] : ['break 0', 'break 1', 'throw']
    assert_equal expected, @query_sql.list_authors.map(&:name).sort
  end

  def test_transaction_timeout_rolls_back_and_keeps_connection_usable
    [:database, :ruby_sleep].each do |kind|
      assert_raises(Timeout::Error) do
        Timeout.timeout(0.05) do
          @query_sql.transaction do |tx|
            tx.create_author_return_id(name: kind.to_s, bio: nil)
            kind == :database ? tx.pause_query(sleep: 0.2) : sleep(0.2)
          end
        end
      end
      assert_empty @query_sql.list_authors
      @query_sql.create_author_return_id(name: 'usable', bio: nil)
      assert_equal ['usable'], @query_sql.list_authors.map(&:name)
      @query_sql.truncate_authors
    end
  end

  def test_transaction_nonlocal_exit_semantics_follow_timeout_version
    break_value = @query_sql.transaction do |tx|
      tx.create_author_return_id(name: 'break', bio: nil)
      break :break_value
    end
    assert_equal :break_value, break_value
    assert_equal :returned, return_from_transaction('return')
    thrown = catch(:transaction_exit) do
      @query_sql.transaction do |tx|
        tx.create_author_return_id(name: 'throw', bio: nil)
        throw :transaction_exit, :throw_value
      end
    end
    assert_equal :throw_value, thrown
    expected = old_timeout_version? ? [] : %w[break return throw]
    assert_equal expected, @query_sql.list_authors.map(&:name).sort
  end

  def test_thread_kill_rolls_back_and_leaves_connection_inactive
    started = Queue.new
    thread = Thread.new do
      @query_sql.transaction do |tx|
        tx.create_author_return_id(name: 'killed', bio: nil)
        started << true
        sleep(5)
      end
    end
    started.pop
    thread.kill
    thread.join
    assert_empty @query_sql.list_authors
    refute @db.transaction_active?
  end

  def test_parent_query_object_calls_are_part_of_same_thread_transaction
    assert_raises(RuntimeError) do
      @query_sql.transaction do |tx|
        tx.create_author_return_id(name: 'tx', bio: nil)
        @query_sql.create_author_return_id(name: 'parent', bio: nil)
        raise 'rollback outer transaction'
      end
    end
    assert_empty @query_sql.list_authors
  end

  # ---- final sweep fixes: :copyfrom conflict clauses, nested modes ------------------------------------------------

  def test_copyfrom_keeps_conflict_clauses
    @query_sql.copy_tags_or_ignore([CopyTagsOrIgnoreArgs.new(name: 'a', uses: 1), CopyTagsOrIgnoreArgs.new(name: 'a', uses: 2)])
    assert_equal [['a', 1]], @query_sql.list_tags.map { |t| [t.name, t.uses] }
    @query_sql.copy_tags_or_replace([CopyTagsOrReplaceArgs.new(name: 'a', uses: 5), CopyTagsOrReplaceArgs.new(name: 'b', uses: 1)])
    assert_equal [['a', 5], ['b', 1]], @query_sql.list_tags.map { |t| [t.name, t.uses] }
    @query_sql.copy_tags_adding_uses([CopyTagsAddingUsesArgs.new(name: 'a', uses: 1), CopyTagsAddingUsesArgs.new(name: 'c', uses: 1)])
    assert_equal [['a', 6], ['b', 1], ['c', 1]], @query_sql.list_tags.map { |t| [t.name, t.uses] }
  end

  def test_nested_transaction_rejects_a_mode
    @query_sql.transaction do |tx|
      assert_raises(ArgumentError) { tx.transaction(mode: :immediate) { nil } }
    end
  end

  def test_seeded_random_copyfrom_round_trip_and_duplicate_is_atomic
    random = seeded_random
    rows = Array.new(300) do |i|
      CopyRegressionRowsArgs.new(id: 5_000_000_000 + i, order: "#{i}#{random_text(random)}",
                                 price: random.rand(3).zero? ? nil : random.rand(1..100) / 101.0,
                                 payload: random.bytes(random.rand(0..64)).b)
    end
    @query_sql.copy_regression_rows(rows)
    expected = rows.map { |r| [r.id, r.order, r.price, r.payload] }.sort_by(&:first)
    actual = @query_sql.list_regression_rows.map { |r| [r.id, r.order, r.price, r.payload] }
    assert_equal expected, actual

    duplicate = [CopyRegressionRowsArgs.new(id: 6_000_000_000, order: 'new', price: nil, payload: nil), rows.first]
    assert_raises(SQLite3::ConstraintException) { @query_sql.copy_regression_rows(duplicate) }
    assert_equal expected, @query_sql.list_regression_rows.map { |r| [r.id, r.order, r.price, r.payload] }
  end

  def test_seeded_random_batch_round_trip
    random = seeded_random
    rows = Array.new(300) do |i|
      { name: "#{i}-#{random_text(random)}", bio: random.rand(3).zero? ? nil : random_text(random) }
    end
    @query_sql.create_authors_batch(rows.map { |row| CreateAuthorsBatchArgs.new(**row) })
    stored = @query_sql.list_authors
    assert_equal rows.sort_by { |row| row[:name] },
                 stored.map { |row| { name: row.name, bio: row.bio } }.sort_by { |row| row[:name] }
    one = @query_sql.get_author_batch(stored.map { |row| GetAuthorBatchArgs.new(id: row.id) })
    assert_equal stored.map(&:name).sort, one.map(&:name).sort
    many = @query_sql.list_authors_by_name_batch(stored.map { |row| ListAuthorsByNameBatchArgs.new(name: row.name) })
    assert_equal stored.map(&:name).sort, many.flatten.map(&:name).sort
  end

  def test_seeded_concurrent_transactions_commit_the_exact_planned_set
    random = seeded_random
    plan = Array.new(4) { Array.new(8) { random.rand(4) } }
    names = plan.each_with_index.map do |actions, thread_index|
      actions.each_index.map { |index| "thread-#{thread_index}-#{index}" }
    end
    expected = plan.each_with_index.flat_map do |actions, thread_index|
      actions.each_with_index.flat_map do |action, index|
        name = names[thread_index][index]
        action == 1 ? [] : (action == 3 ? [name, "#{name}-batch"] : [name])
      end
    end.sort
    threads = plan.each_with_index.map do |actions, thread_index|
      Thread.new do
        actions.each_with_index do |action, index|
          name = names[thread_index][index]
          begin
            @query_sql.transaction do |tx|
              tx.create_author_return_id(name: name, bio: nil)
              case action
              when 1
                raise "rollback #{name}"
              when 2
                begin
                  tx.transaction do |inner|
                    inner.create_author_return_id(name: "#{name}-nested", bio: nil)
                    raise "savepoint #{name}"
                  end
                rescue RuntimeError
                  nil
                end
              when 3
                tx.create_authors_batch([CreateAuthorsBatchArgs.new(name: "#{name}-batch", bio: "batch #{name}")])
              end
            end
          rescue RuntimeError => error
            raise unless action == 1 && error.message == "rollback #{name}"
          end
        end
      end
    end
    threads.each(&:value)
    assert_equal expected, @query_sql.list_authors.map(&:name).sort
  end
  # ---- result column names -------------------------------------------------------------------------------------

  def test_unnamed_result_columns_are_read_by_position
    row = @query_sql.get_unnamed_columns
    assert_equal({ column_1: 1, column_2: 'two' }, row.to_h)
  end

  def test_alias_with_a_quote_is_read
    assert_equal({ it_s: 1 }, @query_sql.get_quoted_alias.to_h)
  end

  def test_not_in_an_empty_slice_matches_everything
    ids = %w[a b].map { |name| create_author(name) }
    assert_equal ids.sort, @query_sql.get_authors_not_in_ids(ids: []).map(&:id)
    assert_equal [ids.last], @query_sql.get_authors_not_in_ids(ids: [ids.first]).map(&:id)
  end

  def test_conflict_that_ends_the_transaction_raises_the_constraint_error
    id = create_author('a')
    assert_raises(SQLite3::ConstraintException) do
      @query_sql.transaction { |tx| tx.create_author_or_rollback(id: id, name: 'dup') }
    end
    assert_raises(SQLite3::ConstraintException) do
      @query_sql.transaction do |tx|
        tx.create_author_return_id(name: 'outer', bio: nil)
        tx.transaction { |inner| inner.create_author_or_rollback(id: id, name: 'dup') }
      end
    end
    refute_predicate @db, :transaction_active?
    assert_equal ['a'], @query_sql.list_authors.map(&:name)
  end
end
