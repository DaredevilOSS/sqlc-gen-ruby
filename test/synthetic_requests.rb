# frozen_string_literal: true

require_relative 'test_helper'

# Extra queries added on top of a captured sqlc request to hit generator paths the example schemas do not:
# 5+ params / columns (multi-line formatting), lower-case query names, several query files, :execrows, ...
module SyntheticRequests
  P = SqlcGenRuby::Plugin
  TYPES = {
    'pg' => %w[bool int4 text float8 bytea],
    'mysql2' => %w[int varchar double blob tinyint],
    'sqlite3' => %w[integer text real blob boolean]
  }.freeze

  module_function

  def column(name, type, not_null: true)
    P::Column.new(name: name, type: P::Identifier.new(name: type), not_null: not_null)
  end

  def query(name, cmd, columns, params, file = 'query.sql')
    # a placeholder for real only when the query has parameters (sqlc never reports fewer parameters than that)
    text = "SELECT 1 -- ? ?\n\t  WHERE a = #{params.empty? ? '1' : '?'}"
    P::Query.new(name: name, cmd: cmd, text: text, columns: columns, filename: file,
                 params: params.each_with_index.map { |c, i| P::Parameter.new(number: i + 1, column: c) })
  end

  def queries(driver)
    cols = TYPES.fetch(driver).each_with_index.map { |type, i| column("c#{i}", type) }
    [
      query('ManyParams', ':one', cols[0, 2], cols), # 5 params -> multi-line formatting
      query('manyRows', ':many', cols, cols[0, 1]), # 5 columns, lower-case name
      query('FourCols', ':many', cols[0, 4], []),
      query('NoCols', ':exec', [], cols, 'other.sql'),
      query('OtherOne', ':one', cols[0, 1], [], 'other.sql'),
      query('CountRows', ':execrows', [], cols[0, 1], 'other.sql'),
      query('WithNumbers2Go', ':exec', [], cols[0, 1], 'my_queries.sql')
    ]
  end

  def extended_request(driver, **options)
    base = PluginHelper.instance_method(:load_request).bind_call(Object.new.extend(PluginHelper), driver, **options)
    base.queries.concat(queries(driver))
    base
  end
end
