#!/usr/bin/env ruby
gem 'minitest'     # ensures using the gem, and not the built-in MT
require 'minitest/autorun'
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
    @query_sql.create_author_return_id(CreateAuthorReturnIdArgs.new(name: name, bio: bio))
  end

  # ---- :one / :many / :exec -------------------------------------------------------------------------------------

  def test_flow
    first = create_author(Consts::BOJACK_AUTHOR, Consts::BOJACK_THEME)
    @query_sql.create_author(CreateAuthorArgs.new(name: Consts::DR_SEUSS_AUTHOR, bio: Consts::DR_SEUSS_QUOTE))

    assert_equal GetAuthorRow.new(first, Consts::BOJACK_AUTHOR, Consts::BOJACK_THEME),
                 @query_sql.get_author(GetAuthorArgs.new(id: first))
    assert_nil @query_sql.get_author(GetAuthorArgs.new(id: -1))
    assert_equal [Consts::BOJACK_AUTHOR, Consts::DR_SEUSS_AUTHOR].sort, @query_sql.list_authors.map(&:name).sort

    @query_sql.delete_author(DeleteAuthorArgs.new(id: first))
    assert_equal [Consts::DR_SEUSS_AUTHOR], @query_sql.list_authors.map(&:name)
  end

  def test_nullable_columns_round_trip_nil
    id = create_author('no bio', nil)
    assert_nil @query_sql.get_author(GetAuthorArgs.new(id: id)).bio
  end

  # ---- :execlastid / :execrows -----------------------------------------------------------------------------------

  def test_execlastid_returns_the_returning_column
    first = create_author('a')
    second = create_author('b')
    assert_kind_of Integer, first
    assert_equal first + 1, second
    assert_kind_of Integer, @query_sql.create_book(CreateBookArgs.new(name: 'book', author_id: first))
  end

  def test_execrows_returns_affected_row_count
    create_author('with bio', 'bio')
    create_author('with bio 2', 'bio')
    create_author('without bio', nil)
    assert_equal 2, @query_sql.update_author_bios(UpdateAuthorBiosArgs.new(bio: 'new bio'))
  end

  # ---- sqlc.arg / sqlc.narg --------------------------------------------------------------------------------------

  def test_numbered_parameters_limit_and_offset
    %w[a b c d].each { |name| create_author(name) }
    page = @query_sql.list_authors_paged(ListAuthorsPagedArgs.new(limit: 2, offset: 1))
    assert_equal %w[b c], page.map(&:name)
  end

  def test_nullable_named_arg
    %w[abc abd xyz].each { |name| create_author(name) }
    assert_equal 3, @query_sql.get_author_by_name_pattern(GetAuthorByNamePatternArgs.new(name_pattern: nil)).size
    ab = @query_sql.get_author_by_name_pattern(GetAuthorByNamePatternArgs.new(name_pattern: 'ab%'))
    assert_equal %w[abc abd], ab.map(&:name).sort
  end

  # ---- sqlc.slice ------------------------------------------------------------------------------------------------

  def test_slice
    ids = %w[a b c].map { |name| create_author(name) }
    got = @query_sql.get_authors_by_ids(GetAuthorsByIdsArgs.new(ids: ids.first(2)))
    assert_equal ids.first(2).sort, got.map(&:id).sort
  end

  def test_empty_slice_matches_nothing
    create_author('a')
    assert_empty @query_sql.get_authors_by_ids(GetAuthorsByIdsArgs.new(ids: []))
  end

  def test_several_slices_in_one_query
    ids = %w[a b c].map { |name| create_author(name) }
    got = @query_sql.get_authors_by_ids_and_names(GetAuthorsByIdsAndNamesArgs.new(ids: ids, names: %w[b c x]))
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
    @query_sql.create_book(CreateBookArgs.new(name: 'book 1', author_id: first))
    @query_sql.create_book(CreateBookArgs.new(name: 'book 2', author_id: second))

    rows = @query_sql.list_all_authors_books
    assert_equal %w[a b], rows.map { |r| r.author.name }
    assert_equal ['book 1', 'book 2'], rows.map { |r| r.book.name }
    assert_equal Author.new(first, 'a', 'bio a'), rows.first.author
    assert_instance_of Book, rows.first.book
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

  def test_declared_types_match_runtime_values
    @db.execute('INSERT INTO authors (id, name, bio) VALUES (1, ?, ?)', ['a', 'b'])
    @db.execute('INSERT INTO authors (id, name, bio) VALUES (2, ?, NULL)', ['c'])
    rbs = File.expand_path('../examples/sqlite3/query_sql.rbs', __dir__)
    @query_sql.list_authors.each { |row| assert_empty RbsTypes.mismatches(row, rbs, 'ListAuthorsRow') }
  end

  # ---- models ----------------------------------------------------------------------------------------------------

  def test_models_are_generated_for_every_table
    assert_equal %i[id name bio], Author.members
    assert_equal %i[id name author_id description], Book.members
  end
end
