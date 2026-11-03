# frozen_string_literal: true

require_relative 'test_helper'
require 'sqlc_gen_ruby/drivers/sqlite3'

class SqlitePlaceholdersTest < Minitest::Test
  Column = Struct.new(:name, :is_sqlc_slice)
  SourceParam = Struct.new(:number, :column)
  Param = Struct.new(:name, :column, :slice)
  Query = Struct.new(:text, :params)

  def setup
    @driver = SqlcGenRuby::Drivers::Sqlite3.new
  end

  def test_scanner_ignores_question_marks_in_literals_and_comments
    sql = "SELECT '?' , \"?4\", `?5`, [?6], ? /* ?7 */ -- ?8\n, /*SLICE:ids*/?, ?2, 'it''s ?9'"

    occurrences = @driver.placeholder_occurrences(sql).map { |kind, value,| [kind, value] }
    assert_equal [[:positional, nil], [:slice, 'ids'], [:numbered, 2]], occurrences
    assert_equal "SELECT '?' , \"?4\", `?5`, [?6], ? /* ?7 */ -- ?8\n, /*SLICE:ids*/?, ?, 'it''s ?9'",
                 @driver.query_text(Query.new(sql, [SourceParam.new(3, Column.new('ids', true))]))
  end

  def test_query_params_follow_sql_occurrence_order_with_repeated_names_and_slices
    sql = "name = ?2 AND id IN (/*SLICE:ids*/?) AND name = ?2 AND id > ? " \
          "AND id IN (/*SLICE:more*/?) AND '?3' != '?' /* ?4 */"
    sources = [
      SourceParam.new(2, Column.new('n', false)),
      SourceParam.new(3, Column.new('ids', true)),
      SourceParam.new(1, Column.new('id', false)),
      SourceParam.new(4, Column.new('more', true))
    ]
    params = [
      Param.new('n', sources[0].column, false),
      Param.new('ids', sources[1].column, true),
      Param.new('id', sources[2].column, false),
      Param.new('more', sources[3].column, true)
    ]
    query = Query.new(sql, sources)

    assert_equal <<~RUBY.chomp, @driver.query_params(query, params)
      query_params = [
        n,
        *ids,
        n,
        id,
        *more
      ]
    RUBY
  end

  def test_numbered_placeholders_are_rewritten_only_for_queries_with_slices
    sliced = Query.new('a = ?2 AND id IN (/*SLICE:ids*/?) AND b = "?3"',
                       [SourceParam.new(3, Column.new('ids', true))])
    plain = Query.new('a = ?2 AND b = "?3"', [])

    assert_equal 'a = ? AND id IN (/*SLICE:ids*/?) AND b = "?3"', @driver.query_text(sliced)
    assert_equal plain.text, @driver.query_text(plain)
  end
end
