#!/usr/bin/env ruby
gem 'minitest'     # ensures using the gem, and not the built-in MT
require 'minitest/autorun'
require 'logger'
require 'stringio'
require 'async'
require 'async/barrier'
require 'bigdecimal'
require 'date'
require 'ipaddr'
require 'securerandom'
require 'timeout'
EXAMPLES_DIR = File.expand_path(ENV.fetch('EXAMPLES_DIR', File.expand_path('../examples', __dir__))).freeze
require_relative 'consts'
require_relative 'rbs_types'
require_relative 'app_helpers'
require 'delegate'
require 'json'
require 'uri'
require File.join(EXAMPLES_DIR, 'pg/query_sql')
RbsTypes.install(Object.const_get("#{ENV.fetch('EXAMPLES_MODULE', 'PgCodegen')}::QuerySql"),
                 File.join(EXAMPLES_DIR, 'pg/query_sql.rbs'))

# End-to-end tests of the code generated for examples/authors/postgresql, against a real PostgreSQL server.
class TestPg < Minitest::Test
  include Object.const_get(ENV.fetch('EXAMPLES_MODULE', 'PgCodegen'))
  include AppHelpers

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
    @query_sql.truncate_test_tables
    @query_sql.truncate_exceptions
  end

  def create_author(name, bio = nil)
    @query_sql.create_author_return_id(name: name, bio: bio)
  end

  # ---- :one / :many / :exec -------------------------------------------------------------------------------------

  def test_flow
    first = @query_sql.create_author(name: Consts::BOJACK_AUTHOR, bio: Consts::BOJACK_THEME)
    assert_equal row_for(CreateAuthorRow, [first.id, Consts::BOJACK_AUTHOR, Consts::BOJACK_THEME]), first
    second = @query_sql.create_author(name: Consts::DR_SEUSS_AUTHOR, bio: Consts::DR_SEUSS_QUOTE)

    assert_equal row_for(GetAuthorRow, [first.id, Consts::BOJACK_AUTHOR, Consts::BOJACK_THEME]),
                 @query_sql.get_author(id: first.id)
    assert_nil @query_sql.get_author(id: -1)
    assert_equal [second.name, first.name].sort, @query_sql.list_authors.map(&:name).sort

    @query_sql.delete_author(id: first.id)
    assert_equal [row_for(ListAuthorsRow, [second.id, Consts::DR_SEUSS_AUTHOR, Consts::DR_SEUSS_QUOTE])],
                 @query_sql.list_authors
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
    assert_nil @query_sql.get_postgres_numeric_types
  end

  # ---- :execlastid / :execrows -----------------------------------------------------------------------------------

  def test_execlastid_returns_the_returning_column
    first = create_author('a')
    second = create_author('b')
    assert_kind_of ::Integer, first
    assert_equal first + 1, second
  end

  def test_execlastid_with_uuid_key
    author_id = create_author('a')
    book_id = @query_sql.create_book(name: 'book', author_id: author_id)
    assert_match(/\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/, book_id)
  end

  def test_execresult_returns_rows_affected
    result = @query_sql.create_author_result(name: 'a', bio: nil)
    assert_equal 1, result.rows_affected
    assert_nil result.last_insert_id
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
    assert_raises(PG::NotNullViolation) { @query_sql.create_authors_batch(rows) }
    assert_equal ['committed'], @query_sql.list_authors.map(&:name)
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

  def test_required_argument_after_optional_named_argument
    %w[alpha beta gamma].each { |name| create_author(name) }
    assert_equal %w[alpha beta gamma], @query_sql.get_authors_by_optional_name(lim: 10).map(&:name).sort
    assert_equal ['beta'], @query_sql.get_authors_by_optional_name(lim: 10, name_filter: 'beta').map(&:name)
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

  def test_copyfrom_keeps_the_case_of_table_and_column_names
    @query_sql.copy_mixed_case_copies([CopyMixedCaseCopiesArgs.new(id: 1, some_value: 'a'), CopyMixedCaseCopiesArgs.new(id: 2, some_value: nil)])
    assert_equal [[1, 'a'], [2, nil]], @query_sql.list_mixed_case_copies.map { |r| r.to_h.values }
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
    assert_equal false, @query_sql.has_authors!.has_any
    create_author('someone')
    assert_equal true, @query_sql.has_authors.has_any
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
    assert_equal row_for(Author, [first, 'a', 'bio a']), rows.first.author
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

  def test_embed_on_the_outer_side_of_a_join_is_nil_without_a_match
    with_book = create_author('a')
    create_author('b')
    @query_sql.create_book(name: 'book', author_id: with_book)
    rows = @query_sql.list_authors_with_optional_book
    assert_equal 'book', rows.first.book.name
    assert_equal 'b', rows.last.author.name
    assert_nil rows.last.book
  end

  def test_repeated_column_parameters_get_distinct_names
    ids = %w[a b c].map { |name| create_author(name) }
    assert_equal [ids[1]], @query_sql.list_authors_between_ids(id: ids[0], id_2: ids[2]).map(&:id)
  end

  def test_keyword_and_method_names_keep_distinct_row_and_argument_names
    args = { id: 1, class_: 'class', end_: 'end', hash: 'hash', method: 'method', count: 7,
             camel_case: 'camel', http_server: 'server', initialize: 'init' }
    @query_sql.insert_name_case(**args)
    row = @query_sql.get_name_case(**args)
    count_member = row.is_a?(::Struct) ? :count_ : :count
    assert_equal %i[id class_ end hash_ method_].concat([count_member, :camelCase, :HTTPServer, :initialize_]), row.class.members
    assert_equal %w[class end hash method], %i[class_ end hash_ method_].map { |member| row.public_send(member) }
    assert_equal 'init', row.initialize_
    assert_equal row, row.with(id: 1) unless row.is_a?(::Struct)
    assert_equal 7, row.public_send(count_member)
    assert_equal 'camel', row.public_send(:camelCase)
    assert_equal 'server', row.public_send(:HTTPServer)
    assert_equal 1, @query_sql.get_http_server(id: 1).id
  end

  # ---- enums -----------------------------------------------------------------------------------------------------

  def test_enum_column
    @query_sql.create_extended_bio(author_name: 'a', name: 'n1', bio_type: ExtendedBioType::MEMOIR)
    @query_sql.create_extended_bio(author_name: 'a', name: 'n2', bio_type: ExtendedBioType::BIOGRAPHY)
    row = @query_sql.get_first_extended_bio_by_type(bio_type: 'Biography')
    assert_equal row_for(GetFirstExtendedBioByTypeRow, %w[a n2 Biography]), row
    assert_equal %w[Autobiography Biography Memoir], ExtendedBioType::ALL
    labels = @query_sql.instance_variable_get(:@db).with do |c|
      c.exec("SELECT unnest(enum_range(NULL::extended.bio_type))::text").column_values(0)
    end
    assert_equal labels, ExtendedBioType::ALL
    assert_equal 'Memoir', ExtendedBioType::MEMOIR
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
    if ENV['PREPARED_STATEMENTS'] == 'false'
      assert_empty @query_sql.list_authors
      return
    end

    pooled = QuerySql.connect(pg_params, size: 3)
    pool = pooled.instance_variable_get(:@db)
    held = Queue.new
    gates = Array.new(3) { Queue.new }
    # three threads, each holding a different connection until it is released
    threads = gates.map do |gate|
      ::Thread.new do
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

  def assert_matches_rbs(row, row_type)
    assert_empty RbsTypes.mismatches(row, File.join(EXAMPLES_DIR, 'pg/query_sql.rbs'), row_type)
  end

  def test_numeric_types_round_trip
    numeric = BigDecimal('12345678901234567890.1234567890123456789012345678901234567890')
    @query_sql.insert_postgres_numeric_types(
      c_boolean: true, c_smallint: -32_768, c_integer: 2_147_483_647, c_bigint: -9_223_372_036_854_775_808,
      c_decimal: BigDecimal('1.5'), c_numeric: numeric, c_real: 1.25, c_double_precision: 0.1 + 0.2, c_money: '12.50',
      c_oid: 42, c_positive: 5
    )
    row = @query_sql.get_postgres_numeric_types
    assert_equal [true, -32_768, 2_147_483_647, -9_223_372_036_854_775_808, BigDecimal('1.5'), numeric, 1.25, 0.1 + 0.2, 42, 5],
                 row.to_h.values_at(:c_boolean, :c_smallint, :c_integer, :c_bigint, :c_decimal, :c_numeric, :c_real,
                                    :c_double_precision, :c_oid, :c_positive)
    assert_kind_of ::Integer, row.c_serial
    assert_includes row.c_money, '12.50'
    assert_matches_rbs(row, 'GetPostgresNumericTypesRow')
    assert_raises(PG::CheckViolation) do
      @query_sql.insert_postgres_numeric_types(**row.to_h.except(:c_serial).merge(c_money: nil, c_positive: -1))
    end
  end

  def test_string_types_round_trip
    @query_sql.insert_postgres_string_types(
      c_char: 'a', c_varchar: 'quote \' 🙂', c_text: "line\nbreak \\ back", c_not_null: 'nn',
      c_xml: '<greeting>Grüße🙂</greeting>', c_tsvector: 'a:1 b:2', c_ltree: 'Top.Science.Astronomy',
      c_hstore: '"key"=>"value", "quoted"=>"two"', c_regclass: 'authors'
    )
    row = @query_sql.get_postgres_string_types
    assert_equal ['a', 'quote \' 🙂', "line\nbreak \\ back", 'nn', '<greeting>Grüße🙂</greeting>', "'a':1 'b':2",
                  'Top.Science.Astronomy', '"key"=>"value", "quoted"=>"two"', 'authors'], row.to_h.values
    assert_matches_rbs(row, 'GetPostgresStringTypesRow')
  end

  def test_datetime_types_round_trip
    timestamp = ::Time.new(2024, 2, 3, 4, 5, Rational(6_123_456, 1_000_000), '+05:30')
    timestamptz = ::Time.new(2024, 3, 4, 5, 6, Rational(7_654_321, 1_000_000), '-07:00')
    @query_sql.insert_postgres_datetime_types(
      c_date: Date.new(2024, 1, 2), c_time: '03:04:05.678', c_timetz: '12:00:00+02', c_timestamp: timestamp,
      c_timestamptz: timestamptz, c_interval: '1 year 2 mons 3 days 04:05:06.789'
    )
    row = @query_sql.get_postgres_datetime_types
    assert_equal [Date.new(2024, 1, 2), '03:04:05.678', '12:00:00+02', timestamp, timestamptz, '1 year 2 mons 3 days 04:05:06.789'],
                 row.to_h.values
    assert_equal timestamptz.utc, row.c_timestamptz.utc
    assert_matches_rbs(row, 'GetPostgresDatetimeTypesRow')
  end

  def array_type_values(id, **values)
    { id: id, c_boolean: nil, c_double_precision: nil, c_text_array: nil, c_integer_array: nil, c_uuid_array: nil,
      c_bio_type_array: nil, c_bytea_array: nil, c_jsonb_array: nil, c_numeric_array: nil, c_timestamptz_array: nil,
      c_integer_matrix: nil, c_text_matrix: nil }.merge(values)
  end

  # includes arrays of types without a decoder (uuid[], enum[]) and multi-dimensional arrays
  def test_array_types_round_trip
    uuids = [SecureRandom.uuid, SecureRandom.uuid]
    matrix = [['', "a,'b", nil], ["back\\slash", "line\nbreak", '🙂']]
    values = array_type_values(
      1, c_text_array: ['x', nil, 'y z'], c_integer_array: [1, 2, 3], c_uuid_array: uuids,
         c_bio_type_array: %w[Memoir Biography], c_bytea_array: ["\x00\xFF".b], c_jsonb_array: [{ 'a' => [1, nil] }],
         c_numeric_array: [BigDecimal('1.25')], c_integer_matrix: [[1, 2], [3, 4]], c_text_matrix: matrix
    )
    @query_sql.insert_postgres_array_types(**values)
    row = @query_sql.list_postgres_array_types.first
    assert_equal values, row.to_h
    assert_matches_rbs(row, 'ListPostgresArrayTypesRow')
  end

  def test_special_types_round_trip
    uuid = '0e52082f-bf69-480e-aff0-1a85139a1074'
    @query_sql.insert_postgres_special_types(
      c_bytea: "\x00\xFF\x01".b, c_bit: '1', c_varbit: '1010010110', c_uuid: uuid, c_inet: '10.1.2.3',
      c_cidr: '192.168.1.0/24', c_macaddr: '08:00:2b:01:02:03', c_point: '(1,2)', c_int4range: '[1,3]', c_dimensions: '(3,4)'
    )
    row = @query_sql.get_postgres_special_types
    assert_equal ["\x00\xFF\x01".b, '1', '1010010110', uuid, IPAddr.new('10.1.2.3'), '08:00:2b:01:02:03', '(1,2)', '[1,4)', '(3,4)'],
                 row.to_h.except(:c_cidr).values.tap { |v| v[0] = v[0].b }
    assert_equal ['192.168.1.0', 24], [row.c_cidr.to_s, row.c_cidr.prefix]
    assert_matches_rbs(row, 'GetPostgresSpecialTypesRow')
  end

  def test_type_families_round_trip_nil
    @query_sql.insert_postgres_numeric_types(c_boolean: nil, c_smallint: nil, c_integer: nil, c_bigint: nil, c_decimal: nil,
                                             c_numeric: nil, c_real: nil, c_double_precision: nil, c_money: nil, c_oid: nil,
                                             c_positive: nil)
    @query_sql.insert_postgres_string_types(c_char: nil, c_varchar: nil, c_text: nil, c_not_null: 'x', c_xml: nil,
                                            c_tsvector: nil, c_ltree: nil, c_hstore: nil, c_regclass: nil)
    @query_sql.insert_postgres_datetime_types(c_date: nil, c_time: nil, c_timetz: nil, c_timestamp: nil, c_timestamptz: nil,
                                              c_interval: nil)
    @query_sql.insert_postgres_array_types(**array_type_values(1))
    @query_sql.insert_postgres_special_types(c_bytea: nil, c_bit: nil, c_varbit: nil, c_uuid: nil, c_inet: nil, c_cidr: nil,
                                             c_macaddr: nil, c_point: nil, c_int4range: nil, c_dimensions: nil)
    {
      'GetPostgresNumericTypesRow' => @query_sql.get_postgres_numeric_types.to_h.except(:c_serial),
      'GetPostgresStringTypesRow' => @query_sql.get_postgres_string_types.to_h.except(:c_not_null),
      'GetPostgresDatetimeTypesRow' => @query_sql.get_postgres_datetime_types.to_h,
      'ListPostgresArrayTypesRow' => @query_sql.list_postgres_array_types.first.to_h.except(:id),
      'GetPostgresSpecialTypesRow' => @query_sql.get_postgres_special_types.to_h
    }.each { |type, values| assert_equal [nil], values.values.uniq, type }
    assert_equal 'x', @query_sql.get_postgres_string_types.c_not_null
  end

  def test_json_and_jsonb_parameters_round_trip_all_json_value_types
    cases = [
      [true, true], [false, false], [7, 7], [1.25, 1.25],
      [{ 'nested' => [1, { 'nil' => nil }] }, { 'nested' => [1, { 'nil' => nil }] }],
      [[1, false, { 'a' => 'b' }], [1, false, { 'a' => 'b' }]],
      ['{"from":"json text"}', { 'from' => 'json text' }],
      [{ 'a' => [1, 2, { 'b' => nil }] }.to_json, { 'a' => [1, 2, { 'b' => nil }] }], [nil, nil]
    ]
    cases.each_with_index do |(value, expected), id|
      @query_sql.insert_postgres_json_types(id: id, c_json: value, c_jsonb: value)
      row = @query_sql.get_postgres_json_types(id: id)
      if expected.nil?
        assert_nil row.c_json
        assert_nil row.c_jsonb
      else
        assert_equal expected, row.c_json
        assert_equal expected, row.c_jsonb
      end
    end
    @query_sql.insert_postgres_json_types(id: 10, c_json: true, c_jsonb: true)
    @query_sql.toggle_postgres_jsonb_type(id: 10)
    assert_equal false, @query_sql.get_postgres_json_types(id: 10).c_jsonb
  end

  def raw_client
    PG.connect(**pg_params.transform_keys(&:to_sym))
  end

  # values written by SQL literals, not by generated parameters, are read with the declared types
  def test_declared_types_match_runtime_values
    client = raw_client
    client.exec(<<~SQL)
      INSERT INTO postgres_numeric_types VALUES (true, 2, 4, 5, 6, 1.5, 2.5, 1.25, 2.25, 3.5, 7, 8);
      INSERT INTO postgres_string_types VALUES ('a', 'b', 'c', 'd', '<x/>', 'e', 'f.g', 'h=>i', 'authors');
      INSERT INTO postgres_datetime_types VALUES ('2024-01-02', '03:04:05', '03:04:05+02', '2024-01-02 03:04:05',
        '2024-01-02 03:04:05+00', '1 day');
      INSERT INTO postgres_json_types VALUES (1, '{"a": 1}', '[1]');
      INSERT INTO postgres_array_types VALUES (1, true, 1.5, '{a}', '{1}', '{0e52082f-bf69-480e-aff0-1a85139a1074}',
        '{Memoir}', '{"\\\\x0102"}', '{"{}"}', '{1.5}', '{"2024-01-02 03:04:05+00"}', '{{1}}', '{{a}}');
      INSERT INTO postgres_special_types VALUES ('\\x0102', B'1', B'101', '0e52082f-bf69-480e-aff0-1a85139a1074',
        '::1', '10.0.0.0/8', '08:00:2b:01:02:03', '(1,2)', '[1,3)', '(3,4)');
    SQL
    rows = { 'GetPostgresNumericTypesRow' => @query_sql.get_postgres_numeric_types,
             'GetPostgresStringTypesRow' => @query_sql.get_postgres_string_types,
             'GetPostgresDatetimeTypesRow' => @query_sql.get_postgres_datetime_types,
             'GetPostgresJSONTypesRow' => @query_sql.get_postgres_json_types(id: 1),
             'ListPostgresArrayTypesRow' => @query_sql.list_postgres_array_types.first,
             'GetPostgresSpecialTypesRow' => @query_sql.get_postgres_special_types }
    rows.each { |type, row| assert_matches_rbs(row, type) }
    assert_equal BigDecimal('1.5'), rows['GetPostgresNumericTypesRow'].c_decimal
    assert_equal Date.new(2024, 1, 2), rows['GetPostgresDatetimeTypesRow'].c_date
    assert_equal [{ 'a' => 1 }, [1]], rows['GetPostgresJSONTypesRow'].to_h.values
    assert_equal ["\x01\x02".b], rows['ListPostgresArrayTypesRow'].c_bytea_array
    assert_equal "\x01\x02".b, rows['GetPostgresSpecialTypesRow'].c_bytea.b
  ensure
    client&.close
  end

  def test_declared_types_match_runtime_values_for_nulls
    client = raw_client
    client.exec(<<~SQL)
      INSERT INTO postgres_numeric_types (c_integer) VALUES (NULL);
      INSERT INTO postgres_string_types (c_text) VALUES (NULL);
      INSERT INTO postgres_datetime_types (c_date) VALUES (NULL);
      INSERT INTO postgres_json_types (id) VALUES (1);
      INSERT INTO postgres_array_types (id) VALUES (1);
      INSERT INTO postgres_special_types (c_uuid) VALUES (NULL);
    SQL
    numeric = @query_sql.get_postgres_numeric_types
    assert_matches_rbs(numeric, 'GetPostgresNumericTypesRow')
    assert_equal [nil], numeric.to_h.except(:c_serial).values.uniq # c_serial is filled by its default
    string = @query_sql.get_postgres_string_types
    assert_matches_rbs(string, 'GetPostgresStringTypesRow')
    assert_equal 'x', string.c_not_null # filled by its default
    assert_equal [nil], string.to_h.except(:c_not_null).values.uniq
    { 'GetPostgresDatetimeTypesRow' => @query_sql.get_postgres_datetime_types,
      'GetPostgresJSONTypesRow' => @query_sql.get_postgres_json_types(id: 1),
      'GetPostgresSpecialTypesRow' => @query_sql.get_postgres_special_types }.each do |type, row|
      assert_matches_rbs(row, type)
      assert_equal [nil], row.to_h.values.uniq, type
    end
    arrays = @query_sql.list_postgres_array_types.first
    assert_matches_rbs(arrays, 'ListPostgresArrayTypesRow')
    assert_equal [nil], arrays.to_h.except(:id).values.uniq
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

  def test_transaction_isolation_level
    @query_sql.transaction(isolation: :serializable) do
      level = @query_sql.instance_variable_get(:@db).with { |c| c.exec('SHOW transaction_isolation').getvalue(0, 0) }
      assert_equal 'serializable', level
    end
    assert_raises(ArgumentError) { @query_sql.transaction(isolation: :bogus) { flunk } }
    @query_sql.instance_variable_get(:@db).with { |c| assert_equal PG::PQTRANS_IDLE, c.transaction_status }
  end

  def test_queries_can_share_an_injected_pool
    pool = ::ConnectionPool.new(size: 2) { PG.connect(**pg_params.transform_keys(&:to_sym)) }
    first = QuerySql.new(pool)
    second = QuerySql.new(pool) # same connections and statement names: must not clash
    id = first.create_author_return_id(name: 'shared', bio: nil)
    assert_equal 'shared', second.get_author(id: id).name
    assert_equal 'shared', first.get_author(id: id).name
    assert_kind_of ::Integer, id # connection was configured on first use (typed results)
  end

  # The generated classes are plain synchronous Ruby; under the Fiber scheduler (the `async` gem) the pooled
  # queries overlap because pg and connection_pool are fiber aware.
  def test_queries_run_concurrently_under_the_fiber_scheduler
    queries = QuerySql.connect(pg_params, size: 5)
    started = ::Process.clock_gettime(::Process::CLOCK_MONOTONIC)
    Sync do
      barrier = Async::Barrier.new
      5.times { barrier.async { queries.pause_query(seconds: 0.4) } }
      barrier.wait
    end
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

  # ---- Ruby conventions: bang finders, logger ----------------------------------------------------------------

  def test_bang_finder_raises_not_found
    id = create_author('a', nil)
    assert_equal 'a', @query_sql.get_author!(id: id).name
    error = assert_raises(QuerySql::NotFound) { @query_sql.get_author!(id: -1) }
    assert_equal 'GetAuthor returned no row', error.message
    assert_nil @query_sql.get_author(id: -1) # the plain finder still returns nil
  end

  def test_every_one_query_has_a_bang_method
    methods = File.read(File.join(EXAMPLES_DIR, 'pg/query_sql.rbs')).scan(/^\s+def (\w+):.* -> \w+Row\?$/).flatten
    refute_empty methods
    methods.each { |name| assert_respond_to @query_sql, "#{name}!" }
  end

  def test_logger_receives_query_names_and_durations
    io = StringIO.new
    logged = QuerySql.connect(pg_params, logger: Logger.new(io, level: Logger::DEBUG))
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
                                 CopyRegressionsArgs.new(id: 2, order: 'b', payload: nil, doc: nil),
                                 CopyRegressionsArgs.new(id: 3, order: 'true', payload: nil, doc: true),
                                 CopyRegressionsArgs.new(id: 4, order: 'false', payload: nil, doc: false)])
    assert_equal [[1, 'a', binary, [1, 2]], [2, 'b', nil, nil], [3, 'true', nil, true], [4, 'false', nil, false]],
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
    query_sql = QuerySql.new(::ConnectionPool.new(size: 1) { client })
    query_sql.list_authors
    client.reset
    assert_empty query_sql.list_authors
  ensure
    client&.close
  end

  def test_batch_parameters_encode_bytea_and_json
    binary = "\x00\xFFb".b
    @query_sql.create_regressions_batch([CreateRegressionsBatchArgs.new(id: 1, order: 'a', payload: binary, doc: [1, { 'k' => 'é' }]),
                                         CreateRegressionsBatchArgs.new(id: 2, order: 'b', payload: nil, doc: nil),
                                         CreateRegressionsBatchArgs.new(id: 3, order: 'c', payload: nil, doc: true),
                                         CreateRegressionsBatchArgs.new(id: 4, order: 'd', payload: nil, doc: false)])
    assert_equal [[1, binary, [1, { 'k' => 'é' }]], [2, nil, nil], [3, nil, true], [4, nil, false]],
                 @query_sql.list_regressions.map { |r| [r.id, r.payload, r.doc] }
  end

  def test_transaction_whose_failed_statement_was_rescued_raises_instead_of_committing
    @query_sql.create_regression(id: 1, order: 'taken', payload: nil, doc: nil, bio_types: nil, uids: nil)
    assert_raises(PG::InFailedSqlTransaction) do
      @query_sql.transaction do |tx|
        tx.create_author_return_id(name: 'lost', bio: nil)
        begin
          tx.create_regression(id: 1, order: 'duplicate', payload: nil, doc: nil, bio_types: nil, uids: nil)
        rescue PG::UniqueViolation
          nil
        end
      end
    end
    assert_empty @query_sql.list_authors
    assert_equal ['taken'], @query_sql.list_regressions.map(&:order)
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
    expected = old_timeout_version? ? [] : ['break 0', 'break 1', 'throw']
    assert_equal expected, @query_sql.list_authors.map(&:name).sort
  end

  # Also with Ruby 3.1's bundled timeout 0.2.0 (CI variant bundled-timeout), whose Timeout leaves the block with throw:
  # the cancelled query must not replace Timeout::Error with PG::InFailedSqlTransaction.
  def test_transaction_timeout_rolls_back_and_keeps_connection_usable
    %i[database ruby_sleep nested_database].each do |kind|
      assert_raises(Timeout::Error) do
        Timeout.timeout(0.05) do
          @query_sql.transaction do |tx|
            tx.create_author_return_id(name: kind.to_s, bio: nil)
            case kind
            when :database then tx.pause_query(seconds: 0.2)
            when :ruby_sleep then sleep(0.2)
            else tx.transaction { |inner| inner.pause_query(seconds: 0.2) }
            end
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

  def test_thread_kill_rolls_back_and_leaves_connection_idle
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
    @query_sql.instance_variable_get(:@db).with do |client|
      assert_equal PG::PQTRANS_IDLE, client.transaction_status
    end
  end

  def wait_until_query_runs(admin, pattern)
    deadline = ::Process.clock_gettime(::Process::CLOCK_MONOTONIC) + 5
    sql = "SELECT 1 FROM pg_stat_activity WHERE state = 'active' AND query LIKE $1 AND pid <> pg_backend_pid()"
    until admin.exec_params(sql, [pattern]).ntuples.positive?
      flunk "no running query like #{pattern}" if ::Process.clock_gettime(::Process::CLOCK_MONOTONIC) > deadline
      sleep 0.01
    end
  end

  # A kill skips `rescue`: the running query used to stay on the pooled connection (PQTRANS_ACTIVE), so the next
  # transaction sent SAVEPOINT instead of BEGIN, and a kill inside a transaction waited for the query to finish.
  def test_thread_kill_during_a_query_cancels_it_and_leaves_the_connection_idle
    queries = QuerySql.connect(pg_params, size: 1)
    admin = PG.connect(**pg_params)
    [false, true].each do |in_transaction|
      worker = ::Thread.new do
        if in_transaction
          queries.transaction do |tx|
            tx.create_author_return_id(name: 'killed', bio: nil)
            tx.pause_query(seconds: 5)
          end
        else
          queries.pause_query(seconds: 5)
        end
      end
      wait_until_query_runs(admin, '%pg_sleep%')
      started = ::Process.clock_gettime(::Process::CLOCK_MONOTONIC)
      worker.kill.join
      assert_operator ::Process.clock_gettime(::Process::CLOCK_MONOTONIC) - started, :<, 2, "in_transaction: #{in_transaction}"
      queries.instance_variable_get(:@db).with do |client|
        assert_equal PG::PQTRANS_IDLE, client.transaction_status
      end
      assert_equal %w[after], queries.transaction { |tx| tx.create_author_return_id(name: 'after', bio: nil) && tx.list_authors.map(&:name) }
      queries.truncate_authors
    end
  ensure
    admin&.close
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

  # ---- final sweep fixes: :batch* / :copyfrom parameter encoding, nested rescued errors, dead connections ---------

  def batch_type_rows
    stamp = ::Time.at(1_700_000_000, 123_456, :usec)
    [{ id: 1, c_boolean: true, c_double_precision: 115_610.38729014261, c_bytea_array: ["\x00\xFF".b, nil],
       c_jsonb_array: [{ 'a' => 1 }, [1, 2], nil], c_integer_array: [], c_numeric_array: [nil, BigDecimal('1.25')],
       c_timestamptz_array: [nil, stamp] },
     { id: 2, c_boolean: false, c_double_precision: 1.0e-305, c_bytea_array: [], c_jsonb_array: [], c_integer_array: [nil],
       c_numeric_array: [], c_timestamptz_array: [] },
     { id: 3, c_boolean: nil, c_double_precision: nil, c_bytea_array: nil, c_jsonb_array: nil, c_integer_array: nil,
       c_numeric_array: nil, c_timestamptz_array: nil }]
  end

  def assert_batch_types_round_trip(rows)
    got = @query_sql.list_postgres_array_types.map(&:to_h)
    assert_equal rows.size, got.size
    rows.zip(got).each do |want, row|
      want.each do |key, value|
        if key == :c_timestamptz_array && value
          assert_equal value.map { |t| t&.to_r }, row[key].map { |t| t&.to_r }, "#{want[:id]} #{key}"
        elsif value.nil?
          assert_nil row[key], "#{want[:id]} #{key}"
        else
          assert_equal value, row[key], "#{want[:id]} #{key}"
        end
      end
    end
  end

  def test_copyfrom_encodes_booleans_floats_and_arrays
    @query_sql.copy_postgres_array_types(batch_type_rows.map { |r| CopyPostgresArrayTypesArgs.new(**r) })
    assert_batch_types_round_trip(batch_type_rows)
  end

  def test_batchexec_encodes_booleans_floats_and_arrays
    @query_sql.insert_postgres_array_types_batch(batch_type_rows.map { |r| InsertPostgresArrayTypesBatchArgs.new(**r) })
    assert_batch_types_round_trip(batch_type_rows)
  end

  def test_array_parameters_need_no_server_side_parameter_types
    # what preparedStatements: false sends: exec_params without prepared parameter types
    params = [9, nil, nil, @query_sql.send(:encode_array, ["\x00".b], :bytea), @query_sql.send(:encode_array, [{ 'a' => 1 }], :json),
              @query_sql.send(:encode_array, []), @query_sql.send(:encode_array, [nil]), @query_sql.send(:encode_array, [nil, ::Time.now])]
    @query_sql.instance_variable_get(:@db).with { |client| client.exec_params(INSERT_POSTGRES_ARRAY_TYPES_BATCH_SQL, params) }
    row = @query_sql.list_postgres_array_types.first
    assert_equal [["\x00".b], [{ 'a' => 1 }], [], [nil]], [row.c_bytea_array, row.c_jsonb_array, row.c_integer_array, row.c_numeric_array]
  end

  def test_all_caps_parameter_names_are_snake_cased
    assert_equal 0, row_value(@query_sql.count_postgres_array_types_above!(min_id: 0), :count)
  end

  def test_nested_transaction_rescuing_a_failed_statement_rolls_back_only_itself
    @query_sql.transaction do |tx|
      tx.create_author(name: 'outer', bio: nil)
      assert_raises(PG::InFailedSqlTransaction) do
        tx.transaction do |inner|
          inner.create_author(name: 'inner', bio: nil)
          assert_raises(PG::Error) { inner.create_book(name: 'b', author_id: -1) } # foreign key violation
        end
      end
      tx.create_author(name: 'outer 2', bio: nil)
    end
    assert_equal ['outer', 'outer 2'], @query_sql.list_authors.map(&:name).sort
  end

  def test_nested_transaction_rejects_an_isolation_level
    @query_sql.transaction do |tx|
      assert_raises(ArgumentError) { tx.transaction(isolation: :serializable) { nil } }
    end
  end

  def test_a_connection_closed_by_the_server_is_reconnected
    pooled = QuerySql.connect(pg_params, size: 1)
    assert_equal [], pooled.list_authors
    pid = pooled.instance_variable_get(:@db).with(&:backend_pid)
    PG.connect(**pg_params.transform_keys(&:to_sym)) { |admin| admin.exec_params('SELECT pg_terminate_backend($1)', [pid]) }
    assert_raises(PG::Error) { pooled.list_authors }
    assert_equal [], pooled.list_authors
  end

  def test_deferred_foreign_key_failure_at_commit_leaves_connection_idle
    assert_raises(PG::ForeignKeyViolation) do
      @query_sql.transaction do |tx|
        tx.create_deferred_book(author_id: -1)
      end
    end
    @query_sql.instance_variable_get(:@db).with do |client|
      assert_equal PG::PQTRANS_IDLE, client.transaction_status
    end
    assert_kind_of ::Integer, @query_sql.create_author_return_id(name: 'usable', bio: nil)
  end

  def test_terminated_backend_inside_transaction_is_replaced
    pooled = QuerySql.connect(pg_params, size: 1)
    assert_raises(PG::Error) do
      pooled.transaction do |tx|
        tx.create_author_return_id(name: 'rolled back', bio: nil)
        pid = pooled.instance_variable_get(:@db).with(&:backend_pid)
        PG.connect(**pg_params.transform_keys(&:to_sym)) do |admin|
          admin.exec_params('SELECT pg_terminate_backend($1)', [pid])
        end
        tx.list_authors
      end
    end
    assert_empty pooled.list_authors
  end

  def test_connection_lost_inside_transaction_is_not_reconnected_until_the_transaction_ends
    pooled = QuerySql.connect(pg_params, size: 1)
    error = assert_raises(PG::ConnectionBad) do
      pooled.transaction do |tx|
        tx.create_author_return_id(name: 'before the loss', bio: nil)
        pid = pooled.instance_variable_get(:@db).with(&:backend_pid)
        PG.connect(**pg_params.transform_keys(&:to_sym)) do |admin|
          admin.exec_params('SELECT pg_terminate_backend($1)', [pid])
          sleep 0.01 while admin.exec_params('SELECT 1 FROM pg_stat_activity WHERE pid = $1', [pid]).ntuples.positive?
        end
        assert_raises(PG::Error) { tx.list_authors }
        # the block rescued the error: later calls must not run on a fresh connection outside the transaction
        assert_raises(PG::ConnectionBad) { tx.create_author_return_id(name: 'after the loss', bio: nil) }
        :committed
      end
    end
    assert_match(/connection was lost/, error.message)
    assert_empty pooled.list_authors
    pooled.instance_variable_get(:@db).with { |client| assert_equal PG::PQTRANS_IDLE, client.transaction_status }
  end

  def test_seeded_random_copyfrom_round_trip_and_duplicate_is_atomic
    random = seeded_random
    rows = Array.new(300) do |i|
      doc = case random.rand(6)
            when 0 then nil
            when 1 then true
            when 2 then false
            when 3 then random.rand(-2**60..2**60)
            when 4 then random.rand(1..100) / 4.0
            else { 'text' => random_text(random), 'items' => [random.rand(100), nil] }
            end
      CopyRegressionsArgs.new(id: 5_000_000_000 + i, order: "#{i}#{random_text(random)}",
                             payload: random.bytes(random.rand(0..16)).b, doc: doc)
    end
    @query_sql.copy_regressions(rows)
    expected = rows.map { |r| [r.id, r.order, r.payload, r.doc] }.sort_by(&:first)
    actual = @query_sql.list_regressions.map { |r| [r.id, r.order, r.payload, r.doc] }
    assert_equal expected, actual

    duplicate = [CopyRegressionsArgs.new(id: 6_000_000_000, order: 'new', payload: nil, doc: nil), rows.first]
    assert_raises(PG::UniqueViolation) { @query_sql.copy_regressions(duplicate) }
    assert_equal expected, @query_sql.list_regressions.map { |r| [r.id, r.order, r.payload, r.doc] }
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
                tx.create_authors_batch([CreateAuthorsBatchArgs.new(name: "#{name}-batch", bio: random_text(random))])
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

  def test_top_level_float_json_parameters_round_trip_exactly
    [0.3304, 0.1 + 0.2, 1.0e-7, -2.5].each_with_index do |value, id|
      @query_sql.insert_postgres_json_types(id: id, c_json: value, c_jsonb: value)
      row = @query_sql.get_postgres_json_types(id: id)
      assert_equal [value, value], [row.c_json, row.c_jsonb]
    end
  end

  # ---- queries abandoned by a timeout ----------------------------------------------------------------------------

  def test_query_abandoned_by_a_timeout_is_cancelled
    queries = QuerySql.connect(pg_params, size: 1)
    [false, true].each do |in_transaction|
      assert_raises(Timeout::Error) do
        Timeout.timeout(0.1) do
          in_transaction ? queries.transaction { |tx| tx.pause_query(seconds: 3) } : queries.pause_query(seconds: 3)
        end
      end
      started = ::Process.clock_gettime(::Process::CLOCK_MONOTONIC)
      queries.list_authors
      assert_operator ::Process.clock_gettime(::Process::CLOCK_MONOTONIC) - started, :<, 1
    end
  end

  # Models named like Ruby core / library constants (Exception, Data, Thread, ...) used to shadow the constants the
  # generated code relies on: a raise in a transaction committed, or the code did not even load.
  CORE_NAMED_MODELS = %i[Exception StandardError Thread Process Data Struct Set String Integer Time Encoding Monitor
                         Mutex ConnectionPool].freeze

  def test_models_named_like_core_constants_do_not_shadow_them
    codegen = Object.const_get(ENV.fetch('EXAMPLES_MODULE', 'PgCodegen'))
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
    QuerySql.connect(pg_params, logger: Logger.new(log)).count_exceptions
    assert_includes log.string, 'count_exceptions'
  end

  # A migration that (re)creates an enum after the pool opened its connections: its arrays are still decoded.
  def test_enum_arrays_of_a_type_created_after_connecting_are_decoded
    query_sql = QuerySql.connect(pg_params, size: 1)
    query_sql.count_exceptions
    admin = PG.connect(**pg_params)
    begin
      admin.exec(<<~SQL)
        DROP SCHEMA late CASCADE;
        CREATE SCHEMA late;
        CREATE TYPE late.mood AS ENUM ('calm', 'happy');
        CREATE TABLE late.feelings (id INTEGER PRIMARY KEY, moods late.mood[] NOT NULL);
      SQL
    ensure
      admin.close
    end
    query_sql.create_late_feeling(id: 1, moods: %w[calm happy])
    assert_equal %w[calm happy], query_sql.get_late_feeling!(id: 1).moods
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
    assert_equal %w[begin end all BEGIN nil self __FILE__], Step::ALL
    assert_equal %w[begin end all BEGIN nil self __FILE__],
                 [Step::BEGIN_, Step::END_, Step::ALL_, Step::BEGIN__2, Step::NIL, Step::SELF, Step::FILE]
    @query_sql.create_regression(id: 1, order: 'steps', payload: nil, doc: nil, bio_types: nil, uids: nil)
    Step::ALL.each { |step| assert_equal step, @query_sql.set_regression_step(id: 1, step: step).step }
  end

  # A PG::Connection whose #exec runs `hook` once, when it is called with `sql`, before (:before) or after (:after)
  # the statement itself: lands an interrupt exactly at BEGIN / COMMIT.
  def interrupting_client(sql, at, &hook)
    client = PG.connect(**pg_params)
    armed = [true]
    client.extend(Module.new do
      define_method(:exec) do |query, *args, &block|
        fire = armed[0] && query == sql
        armed[0] = false if fire
        hook.call if fire && at == :before
        result = super(query, *args, &block)
        hook.call if fire && at == :after
        result
      end
    end)
    client
  end

  def test_interrupts_around_begin_and_commit_never_leave_the_connection_in_a_transaction
    [
      ['BEGIN', :after, :thread_raise], # Timeout / Thread#raise arriving right after BEGIN
      ['BEGIN', :after, :raise],        # raised from BEGIN itself (an Async task stopped while it waits)
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
      assert_equal PG::PQTRANS_IDLE, client.transaction_status, "#{sql} #{kind}"
      query_sql.transaction { |tx| tx.create_author_return_id(name: 'committed', bio: nil) }
      query_sql.create_author_return_id(name: 'autocommitted', bio: nil)
      assert_equal %w[autocommitted committed], @query_sql.list_authors.map(&:name).sort, "#{sql} #{kind}"
      @query_sql.truncate_authors
    ensure
      client&.close
    end
  end

  def test_statements_are_prepared_again_after_deallocate_all
    client = PG.connect(**pg_params)
    query_sql = QuerySql.new(::ConnectionPool.new(size: 1) { client })
    create_author('kept')
    ['DEALLOCATE ALL', 'DISCARD ALL'].each do |sql|
      assert_equal ['kept'], query_sql.list_authors.map(&:name)
      client.exec(sql)
      assert_equal ['kept'], query_sql.list_authors.map(&:name), sql
    end
    # inside a transaction the failed statement has already aborted it: it rolls back, later calls prepare again
    deallocated = lambda do
      query_sql.transaction do |tx|
        client.exec('DEALLOCATE ALL')
        tx.list_authors.map(&:name)
      end
    end
    if ENV['PREPARED_STATEMENTS'] == 'false'
      assert_equal ['kept'], deallocated.call
    else
      assert_raises(PG::InvalidSqlStatementName, &deallocated)
    end
    assert_equal ['kept'], query_sql.list_authors.map(&:name)
  ensure
    client&.close
  end

  # A migration changing a column's type: PostgreSQL refuses the prepared plan ("cached plan must not change result
  # type"); the statement is prepared again outside a transaction, and by the next call after one it aborted.
  def test_statements_are_prepared_again_after_a_column_type_change
    queries = QuerySql.connect(pg_params, size: 1)
    admin = PG.connect(**pg_params)
    id = create_author('kept')
    assert_equal 'kept', queries.get_author(id: id).name
    admin.exec('ALTER TABLE authors ALTER COLUMN name TYPE varchar(200)')
    assert_equal 'kept', queries.get_author(id: id).name
    admin.exec('ALTER TABLE authors ALTER COLUMN name TYPE text')
    in_transaction = -> { queries.transaction { |tx| tx.get_author(id: id).name } }
    if ENV['PREPARED_STATEMENTS'] == 'false'
      assert_equal 'kept', in_transaction.call
    else
      assert_raises(PG::FeatureNotSupported, &in_transaction)
    end
    assert_equal 'kept', in_transaction.call
    assert_equal 'kept', queries.get_author(id: id).name
  ensure
    admin&.exec('ALTER TABLE authors ALTER COLUMN name TYPE text')
    admin&.close
  end

  # A DateTime is written as the instant it stands for (the pg gem alone would encode it as a Date: midnight).
  def test_datetime_parameters_keep_their_instant
    saved = ENV.fetch('TZ', nil)
    ENV['TZ'] = 'XYZ-3' # UTC+3, also on Windows
    [::DateTime.new(2024, 1, 1, 10, 0, Rational(61, 2), '+02:00'), ::DateTime.new(2024, 7, 1, 23, 30, 0, '-07:00')].each do |datetime|
      @query_sql.insert_postgres_datetime_types(c_date: nil, c_time: nil, c_timetz: nil, c_timestamp: datetime, c_timestamptz: datetime,
                                                c_interval: nil)
      row = @query_sql.get_postgres_datetime_types
      assert_equal datetime.to_time, row.c_timestamp, datetime.inspect
      assert_equal datetime.to_time, row.c_timestamptz, datetime.inspect
      @query_sql.truncate_test_tables
    end
  ensure
    saved ? ENV['TZ'] = saved : ENV.delete('TZ')
  end

  # A Time with any UTC offset keeps its instant in a `timestamp` (without time zone) column, read back as a local
  # time; PostgreSQL ignores the offset of a timestamp literal, so it used to store the wall clock of the given zone.
  def test_timestamp_parameters_keep_their_instant_whatever_their_offset
    saved = ENV.fetch('TZ', nil)
    ENV['TZ'] = 'XYZ-3' # UTC+3, also on Windows
    [::Time.utc(2024, 1, 15, 12, 0, Rational(1, 2)), ::Time.new(2024, 2, 3, 4, 5, 6, '+05:30'),
     ::Time.new(2024, 7, 1, 23, 30, 0, '-07:00'), ::Time.at(::Time.now.to_i)].each do |time|
      @query_sql.insert_postgres_datetime_types(c_date: nil, c_time: nil, c_timetz: nil, c_timestamp: time, c_timestamptz: time,
                                                c_interval: nil)
      row = @query_sql.get_postgres_datetime_types
      assert_equal time, row.c_timestamp, time.inspect
      assert_equal time, row.c_timestamptz, time.inspect
      @query_sql.truncate_test_tables
    end
  ensure
    saved ? ENV['TZ'] = saved : ENV.delete('TZ')
  end

  # A connection whose next PREPAREs run the given procs after the server prepared the statement
  def client_with_hooks_after_prepare(hooks)
    client = PG.connect(**pg_params)
    client.singleton_class.prepend(Module.new do
      define_method(:prepare) { |*args| super(*args).tap { hooks.shift&.call } }
    end)
    client
  end

  def test_an_interrupt_during_prepare_leaves_the_statement_usable
    skip 'prepared statements are disabled' if ENV['PREPARED_STATEMENTS'] == 'false'
    prepared = ::Queue.new
    client = client_with_hooks_after_prepare([-> { prepared << true; sleep 1 }]) # rubocop:disable Style/Semicolon
    query_sql = QuerySql.new(::ConnectionPool.new(size: 1) { client })
    create_author('kept')
    worker = ::Thread.new { query_sql.list_authors }
    worker.report_on_exception = false
    prepared.pop
    worker.raise(::Timeout::Error, 'interrupted while preparing')
    assert_raises(::Timeout::Error) { worker.join }
    assert_equal ['kept'], query_sql.list_authors.map(&:name)
  ensure
    client&.close
  end

  # an exception raised by PREPARE itself (a stopped Async task) after the server prepared the statement
  def test_a_statement_left_prepared_by_a_failed_prepare_is_used
    skip 'prepared statements are disabled' if ENV['PREPARED_STATEMENTS'] == 'false'
    stopped = ::Class.new(::StandardError)
    hooks = [-> { raise stopped }]
    client = client_with_hooks_after_prepare(hooks)
    query_sql = QuerySql.new(::ConnectionPool.new(size: 1) { client })
    create_author('kept')
    assert_raises(stopped) { query_sql.list_authors }
    assert_equal ['kept'], query_sql.list_authors.map(&:name)
    # inside a transaction the failed PREPARE has aborted it: it rolls back, later calls use the statement
    hooks << -> { raise stopped }
    assert_raises(stopped) { query_sql.has_authors }
    assert_raises(PG::DuplicatePstatement) { query_sql.transaction(&:has_authors) }
    assert query_sql.transaction(&:has_authors!).has_any
    assert query_sql.has_authors!.has_any
  ensure
    client&.close
  end

  # ---- usage patterns of applications ----------------------------------------------------------------------------

  def pg_connection(**options)
    PG.connect(**pg_params.transform_keys(&:to_sym), **options)
  end

  # Puma / Sidekiq / Resque fork workers from a parent that already ran queries. connection_pool drops the pooled
  # connections in the child (after_fork), and a connection inherited outside a pool is reconnected there: either
  # way the parent's sessions stay usable. A pooled connection the application closed before does not break the fork.
  def test_a_forked_child_leaves_the_parent_connections_usable
    skip_without_fork
    # libpq's GSS probe crashes a forked child on macOS (the usual PGGSSENCMODE=disable advice for Puma there).
    params = pg_params.merge('gssencmode' => 'disable')
    pooled = QuerySql.connect(params, size: 1)
    closed = QuerySql.connect(params, size: 1)
    closed.list_authors
    closed.instance_variable_get(:@db).with(&:close)
    client = pg_connection(gssencmode: 'disable')
    single = QuerySql.new(SingleConnection.new(client))
    id = pooled.create_author_return_id(name: 'before fork', bio: nil)
    assert_equal 'before fork', single.get_author!(id: id).name
    parent_backends = [pooled, single].map { |q| q.instance_variable_get(:@db).with(&:backend_pid) }
    child = in_forked_child do
      [pooled.get_author!(id: id).name, single.get_author!(id: id).name,
       pooled.create_author_return_id(name: 'from child', bio: nil).class,
       [pooled, single].map { |q| q.instance_variable_get(:@db).with(&:backend_pid) }.intersect?(parent_backends)]
    end
    assert_equal ['before fork', 'before fork', ::Integer, false], child
    assert_equal ['before fork', 'from child'], pooled.list_authors.map(&:name).sort
    assert_equal 2, single.list_authors.size
    assert_equal 2, pooled.transaction { |tx| tx.list_authors.size }
    assert_equal parent_backends, [pooled, single].map { |q| q.instance_variable_get(:@db).with(&:backend_pid) }
  ensure
    client&.close
  end

  # A worker forked while another thread has a pooled connection checked out (a Puma thread mid-request, a heartbeat
  # thread during a Resque fork), and a direct connection the child never uses: the child's plain exit leaves both of
  # the parent's sessions open.
  def test_a_child_exit_leaves_connections_checked_out_or_unused_at_fork_open
    skip_without_fork
    params = pg_params.merge('gssencmode' => 'disable')
    pooled = QuerySql.connect(params, size: 2)
    client = pg_connection(gssencmode: 'disable')
    direct = QuerySql.new(SingleConnection.new(client))
    direct.list_authors
    ready = ::Queue.new
    go = ::Queue.new
    worker = ::Thread.new do
      pooled.transaction do |tx|
        tx.list_authors
        ready << true
        go.pop
        tx.list_authors.size
      end
    end
    ready.pop
    assert_equal 0, exit_forked_child
    go << true
    assert_equal 0, worker.value
    assert_equal [], direct.list_authors
    assert_equal 0, pooled.list_authors.size
  ensure
    go&.push(true)
    client&.close
  end

  # A raw connection the application also uses through another library (ActiveRecord's raw_connection, Sequel, a
  # hand-written repository) keeps that library's type maps and field names, and the generated rows stay typed
  # whatever the library sets later.
  def test_a_connection_shared_with_another_library_keeps_its_settings
    client = pg_connection
    results = PG::TypeMapAllStrings.new
    queries = PG::TypeMapByClass.new
    client.type_map_for_results = results
    client.type_map_for_queries = queries
    client.field_name_type = :symbol
    shared = QuerySql.new(SingleConnection.new(client))
    id = shared.create_author_return_id(name: 'shared', bio: nil)
    assert_kind_of ::Integer, id
    assert_equal [id], shared.get_authors_by_ids(param1: [id]).map(&:id)
    shared.copy_authors([CopyAuthorsArgs.new(name: 'copied', bio: nil)])
    assert_equal %w[copied shared], shared.transaction { |tx| tx.list_authors.map(&:name).sort }
    assert_same results, client.type_map_for_results
    assert_same queries, client.type_map_for_queries
    assert_equal :symbol, client.field_name_type
    assert_equal [{ id: id.to_s }], client.exec("SELECT id FROM authors WHERE name = 'shared'").to_a

    client.type_map_for_results = PG::TypeMapByOid.new
    client.field_name_type = :string
    row = shared.get_author!(id: id)
    assert_equal [id, 'shared'], [row.id, row.name]
  ensure
    client&.close
  end

  # DATABASE_URL (Heroku, Render, Kamal, docker-compose) is passed as it is.
  def test_connect_accepts_a_connection_url
    params = pg_params
    url = "postgresql://#{URI.encode_www_form_component(params.fetch('user'))}:" \
          "#{URI.encode_www_form_component(params.fetch('password', ''))}@#{params.fetch('host', 'localhost')}:" \
          "#{params.fetch('port', 5432)}/#{params.fetch('dbname')}"
    from_url = QuerySql.connect(url, size: 1)
    id = from_url.create_author_return_id(name: 'from url', bio: nil)
    assert_equal 'from url', @query_sql.get_author!(id: id).name
  end

  # A transaction already opened on the connection by another library (ActiveRecord::Base.transaction on the same
  # raw connection) becomes the outer transaction: #transaction is a savepoint inside it.
  def test_transaction_inside_a_transaction_opened_by_another_library_is_a_savepoint
    client = pg_connection
    shared = QuerySql.new(SingleConnection.new(client))
    client.exec('BEGIN')
    client.exec("INSERT INTO authors (name) VALUES ('outer')")
    shared.transaction { |tx| tx.create_author_return_id(name: 'inner committed', bio: nil) }
    assert_raises(RuntimeError) do
      shared.transaction do |tx|
        tx.create_author_return_id(name: 'inner rolled back', bio: nil)
        raise 'rollback the savepoint'
      end
    end
    assert_equal PG::PQTRANS_INTRANS, client.transaction_status
    assert_equal ['inner committed', 'outer'], shared.list_authors.map(&:name).sort
    assert_empty @query_sql.list_authors # nothing committed yet
    client.exec('ROLLBACK')
    assert_empty @query_sql.list_authors
  ensure
    client&.close
  end

  # Schema-per-tenant apps (apartment, acts_as_tenant with schemas) switch search_path on a pooled connection: the
  # statements prepared for one tenant read the tables of the next one.
  def test_queries_follow_the_search_path_of_each_tenant
    client = pg_connection
    tenants = %w[sqlc_tenant_a sqlc_tenant_b]
    tenants.each do |tenant|
      client.exec("DROP SCHEMA IF EXISTS #{tenant} CASCADE; CREATE SCHEMA #{tenant}; " \
                  "CREATE TABLE #{tenant}.authors (LIKE public.authors INCLUDING ALL)")
    end
    shared = QuerySql.new(SingleConnection.new(client))
    tenants.each do |tenant|
      client.exec("SET search_path TO #{tenant}")
      shared.create_author_return_id(name: "#{tenant} author", bio: nil)
    end
    tenants.reverse_each do |tenant|
      client.exec("SET search_path TO #{tenant}")
      assert_equal ["#{tenant} author"], shared.list_authors.map(&:name)
    end
    client.exec('SET search_path TO public')
    assert_empty shared.list_authors
  ensure
    tenants&.each { |tenant| client&.exec("DROP SCHEMA IF EXISTS #{tenant} CASCADE") }
    client&.close
  end

  # Reads go to a replica query object, writes to the primary: a write sent to the read-only replica raises the
  # driver's error and leaves the replica usable.
  def test_primary_and_read_replica_query_objects
    replica = QuerySql.connect(pg_params.merge('options' => '-c default_transaction_read_only=on'), size: 1)
    id = @query_sql.create_author_return_id(name: 'primary', bio: nil)
    assert_equal 'primary', replica.get_author!(id: id).name
    assert_raises(PG::ReadOnlySqlTransaction) { replica.create_author_return_id(name: 'replica', bio: nil) }
    assert_raises(PG::ReadOnlySqlTransaction) do
      replica.transaction { |tx| tx.create_author_return_id(name: 'replica', bio: nil) }
    end
    assert_equal ['primary'], replica.list_authors.map(&:name)
  end

  # Query objects memoized in a frozen constant, subclassed (caching, scoping) and wrapped (SimpleDelegator,
  # prepended instrumentation forwarding `...` / `**`), also inside transactions.
  def test_memoized_frozen_subclassed_and_wrapped_query_objects
    memoized = QuerySql.connect(pg_params, size: 2).freeze
    id = memoized.create_author_return_id(name: 'memoized', bio: nil)
    instrumentation = Module.new do
      def calls = @calls ||= []

      def get_author(**args)
        calls << args
        super
      end

      def list_authors(...)
        calls << :list
        super
      end
    end
    caching = Class.new(QuerySql) do
      prepend instrumentation
      def get_author(id:) = (@cache ||= {}).fetch(id) { @cache[id] = super }
    end
    cached = caching.new(memoized.instance_variable_get(:@db))
    assert_equal 'memoized', cached.get_author!(id: id).name
    assert_same cached.get_author(id: id), cached.get_author(id: id)
    assert_equal [{ id: id }] * 3, cached.calls
    in_tx = cached.transaction { |tx| [tx.class, tx.get_author!(id: id).name, tx.list_authors.size] }
    assert_equal [caching, 'memoized', 1], in_tx
    repository = SimpleDelegator.new(memoized)
    assert_equal 'memoized', repository.public_send(:get_author, **{ id: id }).name
    assert_equal ['memoized'], repository.transaction { |tx| tx.list_authors.map(&:name) }
    assert_equal [1, 1], Array.new(2) { ::Thread.new { memoized.list_authors.size } }.map(&:value)
  end

  # Rows cached with Marshal (Rails.cache, Sidekiq-style payloads) and serialized as JSON (API responses).
  def test_rows_round_trip_through_marshal_and_json
    id = create_author('json "author"', "bio\nwith é")
    row = @query_sql.get_author!(id: id)
    assert_equal row, ::Marshal.load(::Marshal.dump(row))
    json = JSON.generate(row.to_h)
    assert_equal({ 'id' => id, 'name' => 'json "author"', 'bio' => "bio\nwith é" }, JSON.parse(json))
    assert_equal row, row.class.new(**JSON.parse(json, symbolize_names: true))
    rows = @query_sql.list_authors
    assert_equal rows, ::Marshal.load(::Marshal.dump(rows))
  end
end
