# frozen_string_literal: true

require_relative 'base'

module SqlcGenRuby
  module Drivers
    # Port of Drivers/Sqlite3Driver.cs. A single SQLite3::Database is injected, so there is no connection
    # pool, and rows are read by index (the sqlite3 gem returns arrays by default).
    class Sqlite3 < Base
      # SQLITE_MAX_VARIABLE_NUMBER was 999 before SQLite 3.32; stay below it for :copyfrom batches.
      MAX_BOUND_PARAMETERS = 999

      def name = 'Sqlite3'

      def init_code = Code.block('def initialize(db)', '@db = db')

      def init_type = "@db: untyped\ndef initialize: (untyped) -> void"

      def transaction_code = Code.block('def transaction', Code.block('@db.transaction do', 'yield self'))

      def prepare_stmt(_func_name, const) = "stmt = client.prepare(#{const})"

      def execute_stmt(_func_name, has_params, array_rows: false)
        has_params ? 'stmt.execute(*query_params)' : 'stmt.execute'
      end

      def pooling_enabled? = false

      def row_data_type = :array

      def closes_statements? = true

      def supports_slice? = true

      def exec_rows_lines(exec) = [exec, 'return client.changes']

      # Relies on a user-written `RETURNING <id>`.
      def exec_last_id_lines(exec, query)
        if query.columns.empty?
          raise ArgumentError, "#{query.name}: :execlastid on SQLite needs a RETURNING clause"
        end

        ["result = #{exec}", 'row = result.first', 'return row[0]']
      end

      # One multi-row `INSERT ... VALUES (?, ?), (?, ?), ...` per batch.
      def copy_from_lines(query, table, columns)
        args = Code.snake_case("#{query.name}Args")
        rows_per_batch = [MAX_BOUND_PARAMETERS / columns.size, 1].max
        placeholders = "(#{(['?'] * columns.size).join(', ')})"
        body = [
          %(sql = "INSERT INTO #{table} (#{columns.join(', ')}) VALUES \#{Array.new(batch.size, '#{placeholders}').join(', ')}"),
          "client.execute(sql, batch.flat_map { |item| [#{columns.map { |c| "item.#{c}" }.join(', ')}] })"
        ].join("\n")
        [Code.block("#{args}.each_slice(#{rows_per_batch}) do |batch|", body)]
      end

      private

      def driver_gems = %w[sqlite3]

      def column_mappings
        @column_mappings ||= [
          mapping('Integer', %w[int integer tinyint smallint mediumint bigint unsignedbigint int2 int8]),
          mapping('bool', %w[boolean bool]),
          mapping('Array[Integer]', %w[blob]),
          mapping('String', %w[character varchar varyingcharacter nchar nativecharacter nvarchar text clob],
                  prefix_based: true),
          mapping('Float', %w[real double doubleprecision float decimal numeric], prefix_based: true)
        ]
      end
    end
  end
end
