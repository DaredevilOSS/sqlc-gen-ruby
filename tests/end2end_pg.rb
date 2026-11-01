#!/usr/bin/env ruby
gem 'minitest'     # ensures using the gem, and not the built-in MT
require 'minitest/autorun'
require 'logger'
require 'stringio'
require 'async'
require 'async/barrier'
require 'bigdecimal'
require 'ipaddr'
require 'securerandom'
require_relative 'consts'
require_relative 'rbs_types'
require_relative '../examples/pg/query_sql'

# End-to-end tests of the code generated for examples/authors/postgresql, against a real PostgreSQL server.
class TestPg < Minitest::Test
  include PgCodegen

  def pg_params
    {
      'dbname' => ENV['DB_NAME'],
      'host' => ENV['POSTGRES_HOST'],
      'port' => ENV['POSTGRES_PORT'], # optional
      'user' => ENV['DB_USER'],
      'password' => ENV['DB_PASS']
    }.compact
  end

  def setup
    @query_sql = QuerySql.connect(pg_params)
    @query_sql.truncate_authors # cascades to books
    @query_sql.truncate_extended_bios
    @query_sql.truncate_extra_types
    @query_sql.truncate_regressions
  end

  def create_author(name, bio = nil)
    @query_sql.create_author_return_id(name: name, bio: bio)
  end

  # ---- :one / :many / :exec -------------------------------------------------------------------------------------

  def test_flow
    first = @query_sql.create_author(name: Consts::BOJACK_AUTHOR, bio: Consts::BOJACK_THEME)
    assert_equal CreateAuthorRow.new(first.id, Consts::BOJACK_AUTHOR, Consts::BOJACK_THEME), first
    second = @query_sql.create_author(name: Consts::DR_SEUSS_AUTHOR, bio: Consts::DR_SEUSS_QUOTE)

    assert_equal GetAuthorRow.new(first.id, Consts::BOJACK_AUTHOR, Consts::BOJACK_THEME),
                 @query_sql.get_author(id: first.id)
    assert_nil @query_sql.get_author(id: -1)
    assert_equal [second.name, first.name].sort, @query_sql.list_authors.map(&:name).sort

    @query_sql.delete_author(id: first.id)
    assert_equal [ListAuthorsRow.new(second.id, Consts::DR_SEUSS_AUTHOR, Consts::DR_SEUSS_QUOTE)],
                 @query_sql.list_authors
  end

  def test_nullable_columns_round_trip_nil
    id = create_author('no bio', nil)
    assert_nil @query_sql.get_author(id: id).bio
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
    book_id = @query_sql.create_book(name: 'book', author_id: author_id)
    assert_match(/\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/, book_id)
  end

  def test_execrows_returns_affected_row_count
    create_author('with bio', 'bio')
    create_author('with bio 2', 'bio')
    create_author('without bio', nil)
    assert_equal 2, @query_sql.update_author_bios(bio: 'new bio')
    assert_equal 0, (@query_sql.truncate_authors; @query_sql.update_author_bios(bio: 'x'))
  end

  # ---- sqlc.arg / sqlc.narg --------------------------------------------------------------------------------------

  def test_named_args_limit_and_offset
    %w[a b c d].each { |name| create_author(name) }
    page = @query_sql.list_authors_paged(limit: 2, offset: 1)
    assert_equal %w[b c], page.map(&:name)
  end

  def test_nullable_named_arg
    %w[abc abd xyz].each { |name| create_author(name) }
    all = @query_sql.get_author_by_name_pattern(name_pattern: nil)
    assert_equal 3, all.size
    ab = @query_sql.get_author_by_name_pattern(name_pattern: 'ab%')
    assert_equal %w[abc abd], ab.map(&:name).sort
  end

  # ---- array parameters (PostgreSQL has no sqlc.slice) -----------------------------------------------------------

  def test_array_parameters
    ids = %w[a b c].map { |name| create_author(name) }
    assert_equal ids.first(2).sort,
                 @query_sql.get_authors_by_ids(param1: ids.first(2)).map(&:id).sort
    assert_empty @query_sql.get_authors_by_ids(param1: [])
    both = @query_sql.get_authors_by_ids_and_names(param1: ids, param2: %w[b c x])
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
    @query_sql.create_book(name: 'book 1', author_id: first)
    @query_sql.create_book(name: 'book 2', author_id: second)

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

  # ---- enums -----------------------------------------------------------------------------------------------------

  def test_enum_column
    @query_sql.create_extended_bio(author_name: 'a', name: 'n1', bio_type: ExtendedBioType::MEMOIR)
    @query_sql.create_extended_bio(author_name: 'a', name: 'n2', bio_type: ExtendedBioType::BIOGRAPHY)
    row = @query_sql.get_first_extended_bio_by_type(bio_type: 'Biography')
    assert_equal GetFirstExtendedBioByTypeRow.new('a', 'n2', 'Biography'), row
    assert_equal %w[Autobiography Biography Memoir], ExtendedBioType::ALL
  end

  def test_enum_rejects_unknown_values
    assert_raises(PG::InvalidTextRepresentation) do
      @query_sql.create_extended_bio(author_name: 'a', name: 'n', bio_type: 'Fiction')
    end
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
    other = QuerySql.connect(pg_params)
    @query_sql.transaction do |tx|
      tx.create_author_return_id(name: 'uncommitted', bio: nil)
      assert_empty other.list_authors
    end
    assert_equal ['uncommitted'], other.list_authors.map(&:name)
  end

  # ---- connection pool -------------------------------------------------------------------------------------------

  def test_every_pooled_connection_prepares_its_own_statements
    pooled = QuerySql.connect(pg_params, size: 3)
    pool = pooled.instance_variable_get(:@db)
    held = Queue.new
    gates = Array.new(3) { Queue.new }
    # three threads, each holding a different connection until it is released
    threads = gates.map do |gate|
      Thread.new do
        pool.with do |client|
          held << client.object_id
          gate.pop
          pooled.list_authors # reentrant: runs on the connection this thread holds
        end
      end
    end
    assert_equal 3, Array.new(3) { held.pop }.uniq.size, 'expected three distinct connections'
    # one after the other, so that the first run has finished (and "remembered" the statement) before the next one
    threads.zip(gates).each do |thread, gate|
      gate << true
      assert_equal [], thread.value
    end
  end

  # ---- more data types -------------------------------------------------------------------------------------------

  def test_extra_types_round_trip
    uuid = '0e52082f-bf69-480e-aff0-1a85139a1074'
    time = Time.utc(2024, 5, 6, 7, 8, 9)
    @query_sql.insert_extra_types(
      c_uuid: uuid, c_jsonb: { 'a' => [1, 2, { 'b' => nil }] }.to_json, c_text_array: ['x', nil, 'y z'],
      c_integer_array: [1, 2, 3], c_timestamptz: time, c_inet: '10.1.2.3', c_money: '12.50', c_not_null: 'nn'
    )
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
    @query_sql.insert_extra_types(
      c_uuid: nil, c_jsonb: nil, c_text_array: nil, c_integer_array: nil, c_timestamptz: nil, c_inet: nil,
      c_money: nil, c_not_null: 'x'
    )
    row = @query_sql.get_extra_types
    assert_equal [nil] * 7, row.to_h.values_at(:c_uuid, :c_jsonb, :c_text_array, :c_integer_array, :c_timestamptz,
                                              :c_inet, :c_money)
  end

  def raw_client
    PG.connect(**pg_params.transform_keys(&:to_sym))
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
    @query_sql.insert_extra_types(
      c_uuid: SecureRandom.uuid, c_jsonb: '[1]', c_text_array: %w[a], c_integer_array: [1], c_timestamptz: Time.now,
      c_inet: '::1', c_money: '1', c_not_null: 'x'
    )
    assert_empty RbsTypes.mismatches(@query_sql.get_extra_types, File.expand_path('../examples/pg/query_sql.rbs', __dir__),
                                     'GetExtraTypesRow')
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

  def test_transaction_isolation_level
    @query_sql.transaction(isolation: :serializable) do
      level = @query_sql.instance_variable_get(:@db).with { |c| c.exec('SHOW transaction_isolation').getvalue(0, 0) }
      assert_equal 'serializable', level
    end
    assert_raises(KeyError) { @query_sql.transaction(isolation: :bogus) { nil } }
  end

  def test_queries_can_share_an_injected_pool
    pool = ConnectionPool.new(size: 2) { PG.connect(**pg_params.transform_keys(&:to_sym)) }
    first = QuerySql.new(pool)
    second = QuerySql.new(pool) # same connections and statement names: must not clash
    id = first.create_author_return_id(name: 'shared', bio: nil)
    assert_equal 'shared', second.get_author(id: id).name
    assert_equal 'shared', first.get_author(id: id).name
    assert_kind_of Integer, id # connection was configured on first use (typed results)
  end

  # The generated classes are plain synchronous Ruby; under the Fiber scheduler (the `async` gem) the pooled
  # queries overlap because pg and connection_pool are fiber aware.
  def test_queries_run_concurrently_under_the_fiber_scheduler
    queries = QuerySql.connect(pg_params, size: 5)
    pool = queries.instance_variable_get(:@db)
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    Sync do
      barrier = Async::Barrier.new
      5.times { barrier.async { pool.with { |client| client.exec('select pg_sleep(0.4)') } } }
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
    logged = QuerySql.connect(pg_params, logger: Logger.new(io, level: Logger::DEBUG))
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
    assert_equal %i[author_name name bio_type], ExtendedBio.members
  end

  # ---- regressions -----------------------------------------------------------------------------------------------

  def test_bytea_json_arrays_and_string_arrays_round_trip
    binary = "\x00\xFFa\x00".b
    uid = SecureRandom.uuid
    row = @query_sql.create_regression!(id: 1, order: 'o', payload: binary, doc: [1, { 'a' => 'é' }],
                                        bio_types: ['Memoir', nil], uids: [uid])
    assert_equal [binary, [1, { 'a' => 'é' }], ['Memoir', nil], [uid]], [row.payload, row.doc, row.bio_types, row.uids]
    assert_equal row.to_h, @query_sql.list_regressions.first.to_h
  end

  def test_execlastid_is_nil_when_no_row_is_returned
    assert_equal 7, @query_sql.create_regression_if_new(id: 7, order: 'first')
    assert_nil @query_sql.create_regression_if_new(id: 7, order: 'again')
  end

  def test_copyfrom_quotes_identifiers_and_encodes_bytea_and_json
    binary = "\x00\x01\xFE".b
    @query_sql.copy_regressions([CopyRegressionsArgs.new(id: 1, order: 'a', payload: binary, doc: [1, 2]),
                                 CopyRegressionsArgs.new(id: 2, order: 'b', payload: nil, doc: nil)])
    assert_equal [[1, 'a', binary, [1, 2]], [2, 'b', nil, nil]],
                 @query_sql.list_regressions.map { |r| [r.id, r.order, r.payload, r.doc] }
  end

  def test_casted_narg_is_optional
    @query_sql.create_regression_if_new(id: 1, order: 'a')
    @query_sql.create_regression_if_new(id: 2, order: 'b')
    assert_equal [1, 2], @query_sql.list_regressions.map(&:id)
    assert_equal [2], @query_sql.list_regressions(order_name: 'b').map(&:id)
  end

  def test_prepared_statements_survive_a_connection_reset
    client = PG.connect(**pg_params)
    query_sql = QuerySql.new(ConnectionPool.new(size: 1) { client })
    query_sql.list_authors
    client.reset
    assert_empty query_sql.list_authors
  ensure
    client&.close
  end

  def test_transaction_left_with_break_or_throw_commits_and_frees_the_connection
    pooled = QuerySql.connect(pg_params, size: 1)
    2.times do |i|
      pooled.transaction do |tx|
        tx.create_author_return_id(name: "break #{i}", bio: nil)
        break
      end
    end
    catch(:out) do
      pooled.transaction do |tx|
        tx.create_author_return_id(name: 'throw', bio: nil)
        throw :out
      end
    end
    pooled.instance_variable_get(:@db).with { |client| assert_equal PG::PQTRANS_IDLE, client.transaction_status }
    assert_equal ['break 0', 'break 1', 'throw'], @query_sql.list_authors.map(&:name).sort
  end
end
