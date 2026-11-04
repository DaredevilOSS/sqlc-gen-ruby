#!/usr/bin/env ruby
gem 'minitest'     # ensures using the gem, and not the built-in MT
require 'minitest/autorun'
require 'logger'
require 'stringio'
require 'json'
require 'bigdecimal'
require 'date'
require 'async'
require 'async/barrier'
require 'timeout'
EXAMPLES_DIR = File.expand_path(ENV.fetch('EXAMPLES_DIR', File.expand_path('../examples', __dir__))).freeze
require_relative 'consts'
require_relative 'rbs_types'
require File.join(EXAMPLES_DIR, 'mysql2/query_sql')
RbsTypes.install(Object.const_get("#{ENV.fetch('EXAMPLES_MODULE', 'Mysql2Codegen')}::QuerySql"),
                 File.join(EXAMPLES_DIR, 'mysql2/query_sql.rbs'))

# End-to-end tests of the code generated for examples/authors/mysql, against a real MySQL / MariaDB server.
class TestMysql2 < Minitest::Test
  include Object.const_get(ENV.fetch('EXAMPLES_MODULE', 'Mysql2Codegen'))

  TEXT_PARTS = ["é", '🙂', "\t", "\n", "\r", '\\', "'", '"', ',', '\N', 'NULL'].freeze

  def row_for(klass, values)
    klass.new(**klass.members.zip(values).to_h)
  end

  def assert_row_layout(row)
    if defined?(::Data) && row.is_a?(::Data)
      assert_predicate row, :frozen?
      assert_equal row.to_h, row.with.to_h
    else
      assert_kind_of ::Struct, row
      assert row.class.keyword_init?
      refute_predicate row, :frozen?
    end
    case row
    in { id:, name: }
      assert_kind_of ::Integer, id
      assert_equal row.name, name
    else
      flunk 'row did not support keyword pattern matching'
    end
  end

  def row_value(row, member)
    actual_member = row.class.members.find { |name| name == member.to_sym || name == :"#{member}_" }
    row.public_send(actual_member)
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

  def mysql2_params
    {
      'database' => ENV['DB_NAME'],
      'host' => ENV['MYSQL_HOST'],
      'port' => ENV['MYSQL_PORT']&.to_i, # optional
      'username' => ENV['DB_USER'],
      'local_infile' => true # required by :copyfrom (LOAD DATA LOCAL INFILE)
    }.compact
  end

  TYPE_TABLES = %w[mysql_numeric_types mysql_string_types mysql_datetime_types mysql_binary_types].freeze

  def setup
    @query_sql = QuerySql.connect(mysql2_params)
    @query_sql.truncate_authors # cascades to books
    @query_sql.truncate_extended_bios
    @query_sql.truncate_regressions
    @query_sql.instance_variable_get(:@db).with do |client|
      TYPE_TABLES.each { |table| client.query("TRUNCATE TABLE #{table}") }
    end
    @query_sql.truncate_name_cases
    @query_sql.truncate_mixed_case_copies
    @query_sql.truncate_exceptions
  end

  def with_time_zone(zone)
    saved = ENV.fetch('TZ', nil)
    ENV['TZ'] = zone
    yield
  ensure
    saved ? ENV['TZ'] = saved : ENV.delete('TZ')
  end

  # Writes each [datetime_value, datetime_2] pair with a bound :exec and with :copyfrom and reads it back.
  # Writes each value with a bound :exec and with :copyfrom and reads it back.
  def assert_times_round_trip(query_sql, values)
    values.each_with_index do |value, i|
      query_sql.insert_mysql_datetime_types(**datetime_values(i + 1).merge(c_datetime_6: value))
    end
    query_sql.copy_mysql_datetime_types(values.each_with_index.map do |value, i|
      CopyMysqlDatetimeTypesArgs.new(id: i + 101, c_datetime_6: value)
    end)
    values.each_with_index do |value, i|
      [i + 1, i + 101].each do |id|
        assert_equal value.to_time, query_sql.get_mysql_datetime_types(id: id).c_datetime_6, "c_datetime_6 of row #{id}"
      end
    end
  end

  def create_author(name, bio = nil)
    @query_sql.create_author_return_id(name: name, bio: bio)
  end

  def numeric_values(id)
    { id: id, c_bool: nil, c_boolean: nil, c_tinyint: nil, c_smallint: nil, c_mediumint: nil, c_int: nil, c_integer: nil,
      c_bigint: nil, c_bigint_unsigned: nil, c_decimal: nil, c_dec: nil, c_numeric: nil, c_fixed: nil, c_decimal_wide: nil,
      c_float: nil, c_double: nil, c_double_precision: nil }
  end

  def string_values(id)
    { id: id, c_char: nil, c_nchar: nil, c_national_char: nil, c_varchar: nil, c_tinytext: nil, c_text: nil, c_mediumtext: nil,
      c_longtext: nil, c_json: nil }
  end

  def datetime_values(id)
    { id: id, c_date: nil, c_time: nil, c_datetime: nil, c_datetime_6: nil, c_timestamp: nil, c_year: nil }
  end

  def binary_values(id)
    { id: id, c_bit: nil, c_bit_16: nil, c_binary: nil, c_varbinary: nil, c_tinyblob: nil, c_blob: nil, c_mediumblob: nil,
      c_longblob: nil }
  end

  def assert_matches_rbs(row, row_type)
    assert_empty RbsTypes.mismatches(row, File.join(EXAMPLES_DIR, 'mysql2/query_sql.rbs'), row_type)
  end

  # ---- :one / :many / :exec -------------------------------------------------------------------------------------

  def test_flow
    first = create_author(Consts::BOJACK_AUTHOR, Consts::BOJACK_THEME)
    @query_sql.create_author(name: Consts::DR_SEUSS_AUTHOR, bio: Consts::DR_SEUSS_QUOTE)

    assert_equal row_for(GetAuthorRow, [first, Consts::BOJACK_AUTHOR, Consts::BOJACK_THEME]),
                 @query_sql.get_author(id: first)
    assert_nil @query_sql.get_author(id: -1)
    assert_equal [Consts::BOJACK_AUTHOR, Consts::DR_SEUSS_AUTHOR].sort, @query_sql.list_authors.map(&:name).sort

    @query_sql.update_author(bio: Consts::DR_SEUSS_NEW_QUOTE, id: first)
    assert_equal Consts::DR_SEUSS_NEW_QUOTE, @query_sql.get_author(id: first).bio

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

  def test_one_on_empty_table_returns_nil
    assert_nil @query_sql.get_mysql_numeric_types(id: 1)
  end

  def test_generated_queries_do_not_create_server_side_prepared_statements
    client = Mysql2::Client.new(mysql2_params)
    database = Object.new
    database.define_singleton_method(:with) { |&block| block.call(client) }
    queries = QuerySql.new(database)
    before = client.query("SHOW SESSION STATUS LIKE 'Com_stmt_prepare'").first.fetch('Value').to_i
    id = queries.create_author_return_id(name: 'plain query', bio: nil)
    20.times { queries.get_author(id: id) }
    after = client.query("SHOW SESSION STATUS LIKE 'Com_stmt_prepare'").first.fetch('Value').to_i
    assert_equal before, after
  ensure
    client&.close
  end

  # ---- :execlastid / :execrows -----------------------------------------------------------------------------------

  def test_execlastid_returns_the_new_id
    first = create_author('a')
    second = create_author('b')
    assert_kind_of ::Integer, first
    assert_equal first + 1, second
    assert_kind_of ::Integer, @query_sql.create_book(name: 'book', author_id: first)
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
    assert_raises(Mysql2::Error) { @query_sql.create_authors_batch(rows) }
    assert_equal ['committed'], @query_sql.list_authors.map(&:name)
  end

  def test_execrows_returns_affected_row_count
    create_author('with bio', 'bio')
    create_author('with bio 2', 'bio')
    create_author('without bio', nil)
    assert_equal 2, @query_sql.update_author_bios(bio: 'new bio')
  end

  def test_execrows_counts_changed_rows_unless_found_rows_is_set
    create_author('same bio', 'same')
    create_author('other bio', 'other')
    assert_equal 1, @query_sql.update_author_bios(bio: 'same')
    found_rows = QuerySql.connect(mysql2_params.merge('flags' => Mysql2::Client::FOUND_ROWS))
    assert_equal 2, found_rows.update_author_bios(bio: 'same')
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

  def test_required_argument_after_optional_named_argument
    %w[alpha beta gamma].each { |name| create_author(name) }
    assert_equal %w[alpha beta gamma], @query_sql.get_authors_by_optional_name(limit: 10).map(&:name).sort
    assert_equal ['beta'], @query_sql.get_authors_by_optional_name(limit: 10, name_filter: 'beta').map(&:name)
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

  # sqlc lowercases MySQL names, but table names are case-sensitive on Linux: LOAD DATA must name `MixedCaseCopies`
  def test_copyfrom_keeps_the_case_of_table_and_column_names
    @query_sql.copy_mixed_case_copies([CopyMixedCaseCopiesArgs.new(id: 1, somevalue: 'a'), CopyMixedCaseCopiesArgs.new(id: 2, somevalue: nil)])
    @query_sql.copy_mixed_case_copies_unquoted([CopyMixedCaseCopiesUnquotedArgs.new(somevalue: 'c', id: 3)])
    assert_equal [[1, 'a'], [2, nil], [3, 'c']], @query_sql.list_mixed_case_copies.map { |r| r.to_h.values }
  end

  def test_copyfrom_takes_any_enumerable
    @query_sql.copy_authors([].lazy)
    assert_empty @query_sql.list_authors
    @query_sql.copy_authors((1..3).lazy.map { |i| CopyAuthorsArgs.new(name: "lazy #{i}", bio: nil) })
    @query_sql.copy_authors(::Enumerator.new { |rows| rows << CopyAuthorsArgs.new(name: 'streamed', bio: nil) })
    assert_equal ['lazy 1', 'lazy 2', 'lazy 3', 'streamed'], @query_sql.list_authors.map(&:name).sort
  end

  # HasAuthors -> has_authors: the query's own name, RuboCop's Naming/PredicatePrefix is disabled for it
  def test_predicate_like_query_names_are_kept
    assert_equal 0, @query_sql.has_authors!.has_any
    create_author('someone')
    assert_equal 1, @query_sql.has_authors.has_any
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

  def test_outer_join_embed_is_nil_without_a_match
    with_book = create_author('a')
    create_author('b')
    @query_sql.create_book(name: 'book', author_id: with_book)
    rows = @query_sql.list_authors_with_optional_book
    assert_equal 'book', rows.first.book.name
    assert_equal 'b', rows.last.author.name
    assert_nil rows.last.book
  end

  # ---- enums / sets ----------------------------------------------------------------------------------------------

  def test_enum_and_set_columns
    @query_sql.create_extended_bio(author_name: 'a', name: 'n1', bio_type: ExtendedBiosBioType::MEMOIR,
                                                            author_type: 'Author,Editor')
    @query_sql.create_extended_bio(author_name: 'a', name: 'n2', bio_type: 'Biography', author_type: nil)
    row = @query_sql.get_first_extended_bio_by_type(bio_type: 'Memoir')
    assert_equal row_for(GetFirstExtendedBioByTypeRow, ['a', 'n1', 'Memoir', 'Author,Editor']), row
    assert_equal %w[Autobiography Biography Memoir], ExtendedBiosBioType::ALL
    assert_equal %w[Author Editor Translator], ExtendedBiosAuthorType::ALL
    @query_sql.instance_variable_get(:@db).with do |client|
      %w[bio_type author_type].zip([ExtendedBiosBioType::ALL, ExtendedBiosAuthorType::ALL]).each do |column, constants|
        column_type = client.query(<<~SQL).first.values.first
          SELECT COLUMN_TYPE FROM information_schema.COLUMNS
          WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'extended_bios' AND COLUMN_NAME = '#{column}'
        SQL
        assert_equal constants, column_type.scan(/'((?:''|[^'])*)'/).flatten
      end
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
    other = QuerySql.connect(mysql2_params)
    @query_sql.transaction do |tx|
      tx.create_author_return_id(name: 'uncommitted', bio: nil)
      assert_empty other.list_authors
    end
    assert_equal ['uncommitted'], other.list_authors.map(&:name)
  end

  # values written by SQL literals, not by generated parameters, are read with the declared types
  def test_declared_types_match_runtime_values
    client = Mysql2::Client.new(mysql2_params)
    client.query(<<~SQL)
      INSERT INTO mysql_numeric_types VALUES (1, 1, 0, 2, 3, 4, 5, 6, 7, 18446744073709551615, 8, 1.5, 2.5, 3.5, 4.5,
        5.5, 1.25, 2.25, 3.25)
    SQL
    client.query("INSERT INTO mysql_string_types VALUES (1, 'a', 'b', 'c', 'dd', 'tt', 'te', 'mt', 'lt', '{\"a\": 1}')")
    client.query(<<~SQL)
      INSERT INTO mysql_datetime_types VALUES (1, '2024-01-02', '03:04:05', '2024-01-02 03:04:05',
        '2024-01-02 03:04:05.123456', '2024-01-02 03:04:05', 2024)
    SQL
    client.query("INSERT INTO mysql_binary_types VALUES (1, b'1', b'1010101010101010', 'x', 'yy', 'tb', 'bl', 'mb', 'lb')")
    numeric = @query_sql.get_mysql_numeric_types(id: 1)
    string = @query_sql.get_mysql_string_types(id: 1)
    datetime = @query_sql.get_mysql_datetime_types(id: 1)
    binary = @query_sql.get_mysql_binary_types(id: 1)
    { 'GetMysqlNumericTypesRow' => numeric, 'GetMysqlStringTypesRow' => string,
      'GetMysqlDatetimeTypesRow' => datetime, 'GetMysqlBinaryTypesRow' => binary }.each do |type, row|
      assert_matches_rbs(row, type)
    end
    assert_equal BigDecimal('1.5'), numeric.c_decimal
    assert_equal 18_446_744_073_709_551_615, numeric.c_bigint_unsigned
    assert_equal({ 'a' => 1 }, JSON.parse(string.c_json))
    assert_equal Date.new(2024, 1, 2), datetime.c_date
    assert_equal 2024, datetime.c_year
    assert_equal [0xAA, 0xAA].pack('C*'), binary.c_bit_16
  ensure
    client&.close
  end

  def test_declared_types_match_runtime_values_for_nulls
    client = Mysql2::Client.new(mysql2_params)
    TYPE_TABLES.each { |table| client.query("INSERT INTO #{table} (id) VALUES (1)") }
    { 'GetMysqlNumericTypesRow' => @query_sql.get_mysql_numeric_types(id: 1),
      'GetMysqlStringTypesRow' => @query_sql.get_mysql_string_types(id: 1),
      'GetMysqlDatetimeTypesRow' => @query_sql.get_mysql_datetime_types(id: 1),
      'GetMysqlBinaryTypesRow' => @query_sql.get_mysql_binary_types(id: 1) }.each do |type, row|
      assert_matches_rbs(row, type)
      assert_equal [nil], row.to_h.except(:id, :c_serial).values.uniq, type # c_serial is filled by its default
    end
  ensure
    client&.close
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

  def test_transaction_isolation_level_is_applied
    @query_sql.transaction(isolation: :serializable) do |tx|
      row = tx.instance_variable_get(:@db).with do |client|
        client.query(<<~SQL).first
          SELECT ISOLATION_LEVEL, STATE
          FROM performance_schema.events_transactions_current
          WHERE THREAD_ID = PS_CURRENT_THREAD_ID()
        SQL
      end
      assert_equal ['SERIALIZABLE', 'ACTIVE'], row.values
    end
    assert_raises(ArgumentError) { @query_sql.transaction(isolation: :bogus) { flunk } }
    @query_sql.instance_variable_get(:@db).with do |client|
      rows = client.query(<<~SQL)
        SELECT STATE
        FROM performance_schema.events_transactions_current
        WHERE THREAD_ID = PS_CURRENT_THREAD_ID()
      SQL
      assert_equal 'COMMITTED', rows.first.fetch('STATE')
    end
  end

  def test_queries_can_share_an_injected_pool
    pool = ::ConnectionPool.new(size: 2) { Mysql2::Client.new(**mysql2_params.transform_keys(&:to_sym)) }
    first = QuerySql.new(pool)
    second = QuerySql.new(pool)
    id = first.create_author_return_id(name: 'shared', bio: nil)
    assert_equal 'shared', second.get_author(id: id).name
  end

  # Both query and transaction paths must use Mysql2::Client#query for Fiber scheduler cooperation.
  def test_generated_queries_overlap_across_threads
    queries = QuerySql.connect(mysql2_params, size: 5)
    started = ::Process.clock_gettime(::Process::CLOCK_MONOTONIC)
    threads = Array.new(5) { ::Thread.new { queries.pause_query(seconds: 0.4) } }
    threads.each(&:value)
    elapsed = ::Process.clock_gettime(::Process::CLOCK_MONOTONIC) - started
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

  def test_generated_queries_overlap_under_sync_including_transactions
    # mysql2 has no non-blocking query on Windows (its C extension blocks the thread there): results only, no overlap
    overlap = !Gem.win_platform?
    queries = QuerySql.connect(mysql2_params, size: 5)
    count = 5
    seconds = 0.3
    started = ::Process.clock_gettime(::Process::CLOCK_MONOTONIC)
    count.times { queries.pause_query(seconds: seconds) }
    serial = ::Process.clock_gettime(::Process::CLOCK_MONOTONIC) - started
    started = ::Process.clock_gettime(::Process::CLOCK_MONOTONIC)
    Sync do
      barrier = Async::Barrier.new
      tasks = Array.new(count) { barrier.async { queries.pause_query(seconds: seconds) } }
      barrier.wait
      tasks.each(&:wait)
    end
    concurrent = ::Process.clock_gettime(::Process::CLOCK_MONOTONIC) - started
    assert_operator concurrent, :<, serial * 0.6,
                    "#{count} generated queries took #{concurrent}s vs #{serial}s serially" if overlap

    started = ::Process.clock_gettime(::Process::CLOCK_MONOTONIC)
    count.times { queries.transaction { |tx| tx.pause_query(seconds: seconds) } }
    serial = ::Process.clock_gettime(::Process::CLOCK_MONOTONIC) - started
    started = ::Process.clock_gettime(::Process::CLOCK_MONOTONIC)
    Sync do
      barrier = Async::Barrier.new
      tasks = Array.new(count) do
        barrier.async { queries.transaction { |tx| tx.pause_query(seconds: seconds) } }
      end
      barrier.wait
      tasks.each(&:wait)
    end
    concurrent = ::Process.clock_gettime(::Process::CLOCK_MONOTONIC) - started
    assert_operator concurrent, :<, serial * 0.6,
                    "#{count} generated transactions took #{concurrent}s vs #{serial}s serially" if overlap
  end

  def test_sql_placeholders_inside_literals_identifiers_and_comments_are_ignored
    id = create_author('quoted ? -- # /* value')
    rows = @query_sql.get_author_with_question_marks(name: 'quoted ? -- # /* value')
    assert_equal [id], rows.map(&:id)
  end

  # every type family round-trips through client-side quoting, with values that need escaping
  def test_client_side_quoting_round_trips_supported_values
    text = "quotes ' \" slash \\ question ? -- # /* NUL \0 emoji 🙂"
    binary = "\x00\xFF\x80\x01".b
    decimal = BigDecimal('12345678901234567890123456789012345.123456789012345678901234567890')
    float = 1.0 / 3
    time = ::Time.new(2024, 2, 3, 4, 5, Rational(6_123_456, 1_000_000), '+05:30')
    date_time = DateTime.new(2024, 3, 4, 5, 6, Rational(7_654_321, 1_000_000), '-07:00')
    numeric = {
      id: 42, c_bool: true, c_boolean: false, c_tinyint: -128, c_smallint: -32_768, c_mediumint: 8_388_607,
      c_int: -2_147_483_648, c_integer: 2_147_483_647, c_bigint: -9_223_372_036_854_775_808,
      c_bigint_unsigned: 18_446_744_073_709_551_615, c_decimal: BigDecimal('1.5'), c_dec: BigDecimal('-2.5'),
      c_numeric: BigDecimal('3.5'), c_fixed: BigDecimal('4.5'), c_decimal_wide: decimal, c_float: 1.25, c_double: float,
      c_double_precision: 0.1 + 0.2
    }
    @query_sql.insert_mysql_numeric_types(**numeric)
    assert_equal numeric.merge(c_bool: 1, c_boolean: 0), @query_sql.get_mysql_numeric_types(id: 42).to_h.except(:c_serial)
    string = { id: 42, c_char: 'a', c_nchar: 'é', c_national_char: '?', c_varchar: "it's 🙂", c_tinytext: text, c_text: text,
               c_mediumtext: text, c_longtext: text, c_json: '{"greeting": "Grüße 🙂", "q": "\\"\'"}' }
    @query_sql.insert_mysql_string_types(**string)
    row = @query_sql.get_mysql_string_types(id: 42)
    assert_equal string.except(:c_json), row.to_h.except(:c_json)
    assert_equal({ 'greeting' => 'Grüße 🙂', 'q' => "\"'" }, JSON.parse(row.c_json))
    @query_sql.insert_mysql_datetime_types(id: 42, c_date: Date.new(2024, 2, 3), c_time: nil, c_datetime: nil,
                                           c_datetime_6: time, c_timestamp: nil, c_year: nil)
    @query_sql.insert_mysql_datetime_types(**datetime_values(43).merge(c_datetime_6: date_time))
    @query_sql.instance_variable_get(:@db).with do |client|
      client.query("UPDATE mysql_datetime_types SET c_year = 2024, c_time = '12:34:56' WHERE id = 42")
    end
    row = @query_sql.get_mysql_datetime_types(id: 42)
    assert_equal [Date.new(2024, 2, 3), time, 2024, ::Time.utc(2000, 1, 1, 12, 34, 56)],
                 [row.c_date, row.c_datetime_6, row.c_year, row.c_time]
    assert_equal [nil, nil], [row.c_datetime, row.c_timestamp]
    assert_equal date_time.to_time, @query_sql.get_mysql_datetime_types(id: 43).c_datetime_6
    binaries = { id: 42, c_bit: nil, c_bit_16: nil, c_binary: "\x00".b, c_varbinary: binary, c_tinyblob: binary,
                 c_blob: binary, c_mediumblob: binary, c_longblob: binary }
    @query_sql.insert_mysql_binary_types(**binaries)
    @query_sql.instance_variable_get(:@db).with do |client|
      client.query("UPDATE mysql_binary_types SET c_bit = b'1', c_bit_16 = b'1010101010101010' WHERE id = 42")
    end
    row = @query_sql.get_mysql_binary_types(id: 42)
    assert_equal binaries.merge(c_bit: "\x01".b, c_bit_16: [0xAA, 0xAA].pack('C*')), row.to_h
    assert_raises(ArgumentError) do
      @query_sql.insert_mysql_numeric_types(**numeric_values(44).merge(c_double: Float::INFINITY))
    end
    { 'GetMysqlNumericTypesRow' => @query_sql.get_mysql_numeric_types(id: 42),
      'GetMysqlStringTypesRow' => @query_sql.get_mysql_string_types(id: 42),
      'GetMysqlDatetimeTypesRow' => @query_sql.get_mysql_datetime_types(id: 42),
      'GetMysqlBinaryTypesRow' => @query_sql.get_mysql_binary_types(id: 42) }.each do |type, value|
      assert_matches_rbs(value, type)
    end
  end

  # mysql2 reads DATETIME values back in its database_timezone (the process zone unless set to :utc), so a Time or
  # DateTime with another offset must keep its instant, through bound parameters and :copyfrom alike.
  def test_time_values_keep_their_instant_whatever_their_offset
    with_time_zone('XYZ-3') do # UTC+3, unlike the values below
      assert_times_round_trip(@query_sql, [::Time.new(2024, 2, 3, 4, 5, Rational(6_123_456, 1_000_000), '+05:30'),
                                           DateTime.new(2024, 3, 4, 5, 6, Rational(7_654_321, 1_000_000), '-07:00'),
                                           ::Time.now.utc.round(6), ::Time.now.round(6)])
    end
  end

  def test_time_values_follow_a_utc_database_timezone
    query_sql = QuerySql.connect(mysql2_params.merge('database_timezone' => :utc))
    with_time_zone('XYZ-3') do
      assert_times_round_trip(query_sql, [::Time.now.round(6), DateTime.new(2024, 3, 4, 5, 6, 7, '+05:30')])
    end
  end

  def test_injection_and_unsupported_parameters_are_safe
    create_author('ordinary')
    assert_empty @query_sql.find_authors_by_exact_name(name: "x' OR '1'='1")
    [Hash.new, Object.new].each do |value|
      assert_raises(TypeError) { @query_sql.find_authors_by_exact_name(name: value) }
    end
    assert_equal ['ordinary'], @query_sql.list_authors.map(&:name)
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
    methods = File.read(File.join(EXAMPLES_DIR, 'mysql2/query_sql.rbs')).scan(/^\s+def (\w+):.* -> \w+Row\?$/).flatten
    refute_empty methods
    methods.each { |name| assert_respond_to @query_sql, "#{name}!" }
  end

  def test_logger_receives_query_names_and_durations
    io = StringIO.new
    logged = QuerySql.connect(mysql2_params, logger: Logger.new(io, level: Logger::DEBUG))
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
    assert_equal %i[author_name name bio_type author_type], ExtendedBio.members
  end

  # ---- regressions -----------------------------------------------------------------------------------------------

  def test_reused_named_parameter_and_unaliased_columns
    @query_sql.copy_regressions([CopyRegressionsArgs.new(order: 'x', note: 'y'),
                                 CopyRegressionsArgs.new(order: 'z', note: 'x'),
                                 CopyRegressionsArgs.new(order: 'z', note: 'z')])
    assert_equal 2, row_value(@query_sql.count_regressions_by_text!(term: 'x'), :count)
  end

  def test_repeated_positional_parameters_get_distinct_names
    @query_sql.copy_regressions(%w[a b c].map { |o| CopyRegressionsArgs.new(order: o, note: nil) })
    assert_equal [[1, 'a'], [3, 'c']], @query_sql.list_regressions_by_ids(id: 1, id_2: 3, id_3: 99).map { |r| [r.id, r.order] }
  end

  def test_keyword_and_method_names_keep_distinct_row_and_argument_names
    args = { id: 1, class_: 'class', end_: 'end', hash: 'hash', method: 'method', count: 7,
             camel_case: 'camel', http_server: 'server', initialize: 'init' }
    @query_sql.insert_name_case(**args)
    row = @query_sql.get_name_case(**args)
    count_member = row.is_a?(::Struct) ? :count_ : :count
    assert_equal %i[id class_ end hash_ method_].concat([count_member, :camelcase, :httpserver, :initialize_]), row.class.members
    assert_equal %w[class end hash method], %i[class_ end hash_ method_].map { |member| row.public_send(member) }
    assert_equal 'init', row.initialize_
    assert_equal row, row.with(id: 1) unless row.is_a?(::Struct)
    assert_equal 7, row.public_send(count_member)
    assert_equal 'camel', row.public_send(:camelcase)
    assert_equal 'server', row.public_send(:httpserver)
    assert_equal 1, @query_sql.get_http_server(id: 1).id
  end

  def test_copyfrom_keeps_strings_that_look_like_null_and_special_characters
    notes = ['NULL', '\N', 'a "quoted", value', 'back\\slash', "new\nline", nil]
    @query_sql.copy_regressions(notes.map { |n| CopyRegressionsArgs.new(order: 'o', note: n) })
    rows = @query_sql.list_regressions_by_ids(id: 1, id_2: 2, id_3: 3) + @query_sql.list_regressions_by_ids(id: 4, id_2: 5, id_3: 6)
    assert_equal notes, rows.map(&:note)
  end

  def test_copyfrom_loads_binary_values
    binary = "\x00\xFF\x01\"\\,\n".b
    @query_sql.copy_regression_rows([CopyRegressionRowsArgs.new(id: 1, order: 'é', note: nil, payload: binary),
                                     CopyRegressionRowsArgs.new(id: 2, order: 'b', note: 'n', payload: nil)])
    assert_equal [[1, binary], [2, nil]], @query_sql.list_regression_rows.map { |r| [r.id, r.payload] }
    assert_equal 'é', @query_sql.list_regressions_by_ids(id: 1, id_2: 0, id_3: 0).first.order
  end

  def test_copyfrom_fails_on_duplicate_keys_and_invalid_values_and_loads_nothing
    @query_sql.copy_regression_rows([CopyRegressionRowsArgs.new(id: 1, order: 'first', note: nil, payload: nil)])
    duplicate = [CopyRegressionRowsArgs.new(id: 2, order: 'new', note: nil, payload: nil),
                 CopyRegressionRowsArgs.new(id: 1, order: 'again', note: nil, payload: nil)]
    assert_raises(Mysql2::Error) { @query_sql.copy_regression_rows(duplicate) }
    assert_raises(Mysql2::Error) { @query_sql.copy_regression_rows([CopyRegressionRowsArgs.new(id: 'x', order: 'bad', note: nil, payload: nil)]) }
    assert_equal [[1, 'first']], @query_sql.list_regressions_by_ids(id: 1, id_2: 2, id_3: 3).map { |r| [r.id, r.order] }
  end

  def test_failed_copyfrom_in_a_transaction_rolls_back_only_itself
    @query_sql.transaction do |tx|
      tx.copy_regression_rows([CopyRegressionRowsArgs.new(id: 1, order: 'kept', note: nil, payload: nil)])
      assert_raises(Mysql2::Error) { tx.copy_regression_rows([CopyRegressionRowsArgs.new(id: 1, order: 'dup', note: nil, payload: nil)]) }
    end
    assert_equal ['kept'], @query_sql.list_regressions_by_ids(id: 1, id_2: 2, id_3: 3).map(&:order)
  end

  def test_transaction_left_with_break_or_throw_commits_and_frees_the_connection
    pooled = QuerySql.connect(mysql2_params, size: 1)
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
    pooled.instance_variable_get(:@db).with { |client| refute client.in_transaction }
    expected = old_timeout_version? ? [] : ['break 0', 'break 1', 'throw']
    assert_equal expected, @query_sql.list_authors.map(&:name).sort
  end

  def test_transaction_timeout_rolls_back_and_keeps_connection_usable
    [:database, :ruby_sleep].each do |kind|
      assert_raises(Timeout::Error) do
        Timeout.timeout(0.05) do
          @query_sql.transaction do |tx|
            tx.create_author_return_id(name: kind.to_s, bio: nil)
            kind == :database ? tx.pause_query(seconds: 0.2) : sleep(0.2)
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

  def test_thread_kill_rolls_back_and_leaves_connection_outside_transaction
    started = Queue.new
    thread = ::Thread.new do
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
    @query_sql.instance_variable_get(:@db).with { |client| refute client.in_transaction }
  end

  def test_thread_kill_during_a_query_replaces_the_connection_and_ends_its_transaction
    pooled = QuerySql.connect(mysql2_params, size: 1)
    id = create_author('kept', 'before')
    [false, true].each do |in_transaction|
      started = Queue.new
      thread = ::Thread.new do
        if in_transaction
          pooled.transaction do |tx|
            tx.update_author(bio: 'killed', id: id)
            started << true
            tx.pause_query(seconds: 1)
          end
        else
          started << true
          pooled.pause_query(seconds: 1)
        end
      end
      started.pop
      sleep 0.2 # inside SLEEP(1)
      thread.kill
      thread.join
      assert_equal [%w[kept before]], pooled.list_authors.map { |a| [a.name, a.bio] }, "in_transaction: #{in_transaction}"
      pooled.instance_variable_get(:@db).with { |client| refute client.in_transaction }
    end
    other = Mysql2::Client.new(**mysql2_params.transform_keys(&:to_sym))
    other.query('SET SESSION innodb_lock_wait_timeout = 5')
    other.query("UPDATE authors SET bio = 'after' WHERE id = #{id}") # the killed transaction's row lock is gone
    assert_equal 'after', @query_sql.get_author(id: id).bio
  ensure
    other&.close
  end

  def test_nested_savepoint_rolls_back_while_outer_transaction_commits
    @query_sql.transaction do |tx|
      tx.create_author_return_id(name: 'outer before', bio: nil)
      assert_raises(RuntimeError) do
        tx.transaction do |inner|
          inner.create_author_return_id(name: 'nested', bio: nil)
          raise 'rollback savepoint'
        end
      end
      tx.create_author_return_id(name: 'outer after', bio: nil)
    end
    assert_equal ['outer after', 'outer before'], @query_sql.list_authors.map(&:name).sort
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

  # ---- final sweep fixes: :copyfrom into JSON, IGNORE / REPLACE, reused statements, dead connections ------------

  def copy_type_rows = @query_sql.list_regression_rows.map { |r| [r.id, r.code, r.doc && JSON.parse(r.doc), r.flags, r.amount] }

  def test_copyfrom_loads_json_next_to_binary_values
    @query_sql.copy_regression_types([CopyRegressionTypesArgs.new(id: 1, code: 'é', doc: '{"a": [1, "é"]}', flags: "\x83".b, amount: 4_000_000_000),
                                      CopyRegressionTypesArgs.new(id: 2, code: 'b', doc: nil, flags: nil, amount: nil)])
    assert_equal [[1, 'é', { 'a' => [1, 'é'] }, "\x83".b, 4_000_000_000], [2, 'b', nil, nil, nil]], copy_type_rows
  end

  def test_copyfrom_keeps_insert_ignore_and_replace
    @query_sql.copy_regressions_ignore([CopyRegressionsIgnoreArgs.new(id: 1, code: 'a'), CopyRegressionsIgnoreArgs.new(id: 1, code: 'b')])
    assert_equal [[1, 'a']], copy_type_rows.map { |r| r.first(2) }
    @query_sql.copy_regressions_replace([CopyRegressionsReplaceArgs.new(id: 1, code: 'c'), CopyRegressionsReplaceArgs.new(id: 2, code: 'd')])
    assert_equal [[1, 'c'], [2, 'd']], copy_type_rows.map { |r| r.first(2) }
  end

  def test_batch_with_binary_parameters_after_an_unsigned_int
    rows = (1..5).map { |i| CreateRegressionsBatchArgs.new(id: i, code: "c#{i}", flags: [0x83 + i].pack('C'), amount: 586_988_122 + i) }
    @query_sql.create_regressions_batch(rows)
    assert_equal(rows.map { |r| [r.id, r.flags, r.amount] }, copy_type_rows.map { |r| [r[0], r[3], r[4]] })
    counts = @query_sql.count_regressions_by_codes([CountRegressionsByCodesArgs.new(code: 'c1', code_2: 'c2')])
    assert_equal [2], counts.map(&:matches)
  end

  def test_nested_transaction_rejects_an_isolation_level
    @query_sql.transaction do |tx|
      assert_raises(ArgumentError) { tx.transaction(isolation: :serializable) { nil } }
    end
  end

  def test_a_connection_closed_by_the_server_is_replaced
    pooled = QuerySql.connect(mysql2_params, size: 1)
    id = pooled.instance_variable_get(:@db).with(&:thread_id)
    admin = Mysql2::Client.new(**mysql2_params.transform_keys(&:to_sym))
    admin.query("KILL #{id}")
    admin.close
    assert_raises(Mysql2::Error) { pooled.list_authors }
    assert_equal [], pooled.list_authors
  end

  def test_killed_backend_inside_transaction_is_replaced
    pooled = QuerySql.connect(mysql2_params, size: 1)
    assert_raises(Mysql2::Error) do
      pooled.transaction do |tx|
        tx.create_author_return_id(name: 'rolled back', bio: nil)
        id = pooled.instance_variable_get(:@db).with(&:thread_id)
        admin = Mysql2::Client.new(**mysql2_params.transform_keys(&:to_sym))
        admin.query("KILL #{id}")
        admin.close
        tx.list_authors
      end
    end
    assert_empty pooled.list_authors
  end

  def test_a_stopped_async_task_does_not_leave_a_closed_connection_in_the_pool
    pooled = QuerySql.connect(mysql2_params, size: 1)
    [false, true].each do |in_transaction|
      assert_empty pooled.list_authors
      Sync do |task|
        query = task.async do
          in_transaction ? pooled.transaction { |tx| tx.pause_query(seconds: 2) } : pooled.pause_query(seconds: 2)
        end
        sleep 0.2
        query.stop
      end
      assert_empty pooled.list_authors, "next call after stopping a query (in_transaction: #{in_transaction})"
    end
  end

  def test_seeded_random_copyfrom_round_trip_and_duplicate_is_atomic
    random = seeded_random
    rows = Array.new(300) do |i|
      CopyRegressionRowsArgs.new(id: 5_000_000_000 + i, order: "#{i}#{random_text(random)}",
                                 note: random.rand(3).zero? ? nil : random_text(random),
                                 payload: random.bytes(random.rand(0..16)).b)
    end
    rows << CopyRegressionRowsArgs.new(id: 5_000_001_000, order: "ctrl-z \x1A text", note: "\x1A", payload: "\x1A\x1A".b)
    @query_sql.copy_regression_rows(rows)
    expected = rows.map { |r| [r.id, r.order, r.note, r.payload] }.sort_by(&:first)
    actual = @query_sql.list_regression_rows.map { |r| [r.id, r.order, r.note, r.payload] }
    assert_equal expected, actual

    duplicate = [CopyRegressionRowsArgs.new(id: 6_000_000_000, order: 'new', note: nil, payload: nil), rows.first]
    assert_raises(Mysql2::Error) { @query_sql.copy_regression_rows(duplicate) }
    assert_equal expected, @query_sql.list_regression_rows.map { |r| [r.id, r.order, r.note, r.payload] }
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
      ::Thread.new do
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

  def test_symbol_enum_value_is_bound_as_its_name
    @query_sql.create_extended_bio(author_name: 'a', name: 'n', bio_type: :Memoir, author_type: nil)
    assert_equal 'Memoir', @query_sql.get_first_extended_bio_by_type(bio_type: :Memoir).bio_type
  end

  def test_deadlock_in_a_nested_transaction_raises_the_deadlock_error
    ids = %w[a b].map { |name| create_author(name) }
    queries = QuerySql.connect(mysql2_params, size: 2)
    locked = Queue.new
    threads = [ids, ids.reverse].map do |first, second|
      ::Thread.new do
        queries.transaction do |tx|
          tx.delete_author(id: first)
          locked << first
          sleep 0.01 until locked.size == 2
          tx.transaction { |inner| inner.delete_author(id: second) }
        end
        nil
      rescue Mysql2::Error => e
        e
      end
    end
    errors = threads.map(&:value).compact
    assert_equal [1213], errors.map(&:error_number), errors.map(&:message).inspect
    assert_empty @query_sql.list_authors
  end

  # Authors another connection locks in #deadlock_on so that InnoDB picks the other transaction as the victim.
  def create_fillers = Array.new(20) { |i| create_author("filler #{i}") }

  # Runs the block (inside a transaction that holds the row `first`) once another connection has locked `second` and
  # the (more) `fillers`, and waits for `first`: the block's next lock on `second` is a deadlock that rolls back the
  # block's whole transaction (InnoDB rolls back the transaction that changed fewer rows).
  def deadlock_on(first, second, fillers)
    other = Mysql2::Client.new(mysql2_params)
    watcher = Mysql2::Client.new(mysql2_params)
    locked = Queue.new
    blocker = ::Thread.new do
      other.query('BEGIN')
      # one primary-key lookup per row: a scan (`id IN (...)` on a small table) would also lock `first`
      [second, *fillers].each { |id| other.query("UPDATE authors SET bio = 'other' WHERE id = #{id}") }
      locked << true
      other.query("UPDATE authors SET bio = 'other' WHERE id = #{first}")
      other.query('ROLLBACK')
    end
    sleep 0.01 while locked.empty? && blocker.alive?
    blocker.value unless blocker.alive? # raises what stopped it
    deadline = ::Time.now + 10
    waiting = 'SELECT COUNT(*) AS n FROM information_schema.innodb_trx ' \
              "WHERE trx_mysql_thread_id = #{other.thread_id} AND trx_state = 'LOCK WAIT'"
    sleep 0.01 until watcher.query(waiting).first['n'] == 1 || ::Time.now > deadline
    yield
  ensure
    blocker&.join(10)
    other&.close
    watcher&.close
  end

  def authors_except_fillers
    @query_sql.list_authors.reject { |author| author.name.start_with?('filler') }.map { |author| [author.name, author.bio] }
  end

  def test_rescued_deadlock_in_a_transaction_raises_instead_of_committing
    first, second = %w[a b].map { |name| create_author(name) }
    fillers = create_fillers
    after_error = nil
    error = assert_raises(Mysql2::Error) do
      @query_sql.transaction do |tx|
        tx.create_author(name: 'before', bio: nil)
        tx.update_author(bio: 'mine', id: first)
        deadlock_on(first, second, fillers) do
          assert_equal 1213, assert_raises(Mysql2::Error) { tx.update_author(bio: 'mine', id: second) }.error_number
        end
        # InnoDB already rolled the whole transaction back: this must not run in autocommit mode
        after_error = assert_raises(Mysql2::Error) { tx.create_author(name: 'after', bio: nil) }
        :committed
      end
    end
    assert_equal [1213, 1213], [error.error_number, after_error.error_number]
    assert_equal [['a', nil], ['b', nil]], authors_except_fillers
    @query_sql.transaction { |tx| tx.create_author(name: 'later', bio: nil) }
    assert_includes authors_except_fillers, ['later', nil]
  end

  def test_rescued_deadlock_in_a_nested_transaction_raises_instead_of_committing
    first, second = %w[a b].map { |name| create_author(name) }
    fillers = create_fillers
    inner_error = nil
    error = assert_raises(Mysql2::Error) do
      @query_sql.transaction do |tx|
        tx.create_author(name: 'before', bio: nil)
        tx.update_author(bio: 'mine', id: first)
        inner_error = assert_raises(Mysql2::Error) do
          tx.transaction { |inner| deadlock_on(first, second, fillers) { inner.update_author(bio: 'mine', id: second) } }
        end
        :committed
      end
    end
    assert_equal [1213, 1213], [inner_error.error_number, error.error_number]
    assert_equal [['a', nil], ['b', nil]], authors_except_fillers
  end

  def test_rescued_lock_wait_timeout_rolls_back_only_its_statement
    first = create_author('a')
    queries = QuerySql.connect(mysql2_params.merge('init_command' => 'SET SESSION innodb_lock_wait_timeout = 1'), size: 1)
    other = Mysql2::Client.new(mysql2_params)
    other.query('BEGIN')
    other.query("UPDATE authors SET bio = 'other' WHERE id = #{first}")
    whole_transaction = other.query('SELECT @@innodb_rollback_on_timeout AS v').first['v'] == 1
    run = lambda do
      queries.transaction do |tx|
        tx.create_author(name: 'before', bio: nil)
        assert_equal 1205, assert_raises(Mysql2::Error) { tx.update_author(bio: 'mine', id: first) }.error_number
        tx.create_author(name: 'after', bio: nil)
        :committed
      end
    end
    if whole_transaction # innodb_rollback_on_timeout=ON rolls the whole transaction back, like a deadlock
      assert_equal 1205, assert_raises(Mysql2::Error) { run.call }.error_number
      assert_equal [['a', nil]], authors_except_fillers
    else
      assert_equal :committed, run.call
      assert_equal [['a', nil], ['after', nil], ['before', nil]], authors_except_fillers
    end
  ensure
    other&.query('ROLLBACK')
    other&.close
  end

  # Models named like Ruby core / library constants (Exception, Data, Thread, ...) used to shadow the constants the
  # generated code relies on: a raise in a transaction committed, or the code did not even load.
  CORE_NAMED_MODELS = %i[Exception StandardError Thread Process Data Struct Set String Integer Time Encoding Monitor
                         Mutex ConnectionPool].freeze

  def test_models_named_like_core_constants_do_not_shadow_them
    codegen = Object.const_get(ENV.fetch('EXAMPLES_MODULE', 'Mysql2Codegen'))
    CORE_NAMED_MODELS.each { |name| assert_equal [:id], codegen.const_get(name, false).members, name }
    assert_raises(::ArgumentError) do
      @query_sql.transaction do |tx|
        tx.create_exception
        raise ::ArgumentError
      end
    end
    assert_equal 0, @query_sql.count_exceptions.n
    @query_sql.transaction(&:create_exception)
    assert_equal 1, @query_sql.count_exceptions!.n
    assert_raises(QuerySql::NotFound) { @query_sql.get_author!(id: -1) }
    log = ::StringIO.new
    QuerySql.connect(mysql2_params, logger: Logger.new(log)).count_exceptions
    assert_includes log.string, 'count_exceptions'
  end

  # The query object #transaction yields keeps its queries in the transaction from other fibers and threads (they
  # used to check another connection out of the pool and commit on their own) and fails once the transaction ended.
  def test_transaction_query_object_works_from_other_fibers_and_threads
    assert_raises(::ArgumentError) do
      @query_sql.transaction do |tx|
        ::Enumerator.new { |y| y << tx.create_exception }.next
        ::Fiber.new { tx.create_exception }.resume
        ::Thread.new { tx.create_exception }.join
        Sync { Async { tx.create_exception }.wait }
        tx.transaction { ::Enumerator.new { |y| y << tx.create_exception }.next }
        assert_equal 5, tx.count_exceptions!.n
        raise ::ArgumentError
      end
    end
    assert_equal 0, @query_sql.count_exceptions!.n
    leaked = @query_sql.transaction { |tx| tx }
    assert_raises(TransactionEnded) { leaked.count_exceptions }
  end

  def test_enum_values_named_like_ruby_keywords_get_valid_constants
    assert_equal %w[begin end all nil self do], RegressionsStep::ALL
    assert_equal %w[begin end all nil self do],
                 [RegressionsStep::BEGIN_, RegressionsStep::END_, RegressionsStep::ALL_, RegressionsStep::NIL,
                  RegressionsStep::SELF, RegressionsStep::DO]
    @query_sql.copy_regression_rows([CopyRegressionRowsArgs.new(id: 1, order: 'steps', note: nil, payload: nil)])
    RegressionsStep::ALL.each do |step|
      @query_sql.set_regression_step(step: step, id: 1)
      assert_equal step, @query_sql.get_regression_step(id: 1).step
    end
  end

  # A Mysql2::Client whose #query runs `hook` once, when it is called with `sql`, before (:before) or after (:after)
  # the statement itself: lands an interrupt exactly at BEGIN / COMMIT.
  def interrupting_client(sql, at, &hook)
    client = Mysql2::Client.new(**mysql2_params)
    armed = [true]
    client.extend(Module.new do
      define_method(:query) do |query, *args, **options, &block|
        fire = armed[0] && query == sql
        armed[0] = false if fire
        hook.call if fire && at == :before
        result = super(query, *args, **options, &block)
        hook.call if fire && at == :after
        result
      end
    end)
    client
  end

  def test_interrupts_around_begin_and_commit_never_leave_the_connection_in_a_transaction
    [
      ['BEGIN', :after, :thread_raise], # Timeout / Thread#raise arriving right after BEGIN
      ['BEGIN', :after, :raise],        # raised from BEGIN after it ran
      ['COMMIT', :before, :raise]       # raised from COMMIT before it reached the server
    ].each do |sql, at, kind|
      began = ::Queue.new
      client = interrupting_client(sql, at) do
        raise ::Timeout::Error, "interrupted at #{sql}" unless kind == :thread_raise

        began << true
        sleep(0.5)
      end
      query_sql = QuerySql.new(::ConnectionPool.new(size: 1) { client })
      thread = ::Thread.new { query_sql.transaction { |tx| tx.create_author_return_id(name: 'interrupted', bio: nil) } }
      if kind == :thread_raise
        began.pop
        thread.raise(::Timeout::Error, "interrupted at #{sql}")
      end
      assert_raises(::Timeout::Error) { thread.join }
      query_sql.create_author_return_id(name: 'autocommitted', bio: nil)
      assert_equal %w[autocommitted], @query_sql.list_authors.map(&:name), "#{sql} #{kind}"
      query_sql.transaction { |tx| tx.create_author_return_id(name: 'committed', bio: nil) }
      assert_equal %w[autocommitted committed], @query_sql.list_authors.map(&:name).sort, "#{sql} #{kind}"
      @query_sql.truncate_authors
    ensure
      client&.close
    end
  end
end
