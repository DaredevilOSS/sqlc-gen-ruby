# frozen_string_literal: true

require_relative 'base'

module SqlcGenRuby
  module Drivers
    # SQLite via the `sqlite3` gem. A single SQLite3::Database is injected, so there is no connection pool, and
    # rows are read by index (the sqlite3 gem returns arrays by default).
    class Sqlite3 < Base
      # SQLITE_MAX_VARIABLE_NUMBER was 999 before SQLite 3.32; stay below it for :copyfrom batches.
      MAX_BOUND_PARAMETERS = 999

      def name = 'Sqlite3'

      def class_methods
        [
          ["# @param db [SQLite3::Database] a single connection (SQLite3::Database is not shared across threads)\n" \
           "def initialize(db)\n  @db = db\nend", 'def initialize: (untyped db) -> void'],
          [TRANSACTION, "def transaction: [T] (?mode: (:deferred | :immediate | :exclusive)?) { (instance) -> T } -> T"]
        ]
      end

      def prepare_stmt(_stmt_name, const) = "stmt = client.prepare(#{const})"

      def execute_stmt(_stmt_name, _const, has_params, array_rows: false)
        has_params ? 'stmt.execute(*query_params)' : 'stmt.execute'
      end

      def pooling_enabled? = false

      def row_data_type = :array

      def closes_statements? = true

      def supports_slice? = true

      def exec_rows_lines(exec) = [exec, 'client.changes']

      # Relies on a user-written `RETURNING <id>`.
      def exec_last_id_lines(exec, query)
        if query.columns.empty?
          raise ArgumentError, "#{query.name}: :execlastid on SQLite needs a RETURNING clause"
        end

        ["result = #{exec}", 'row = result.first', 'row && row[0]']
      end

      # One multi-row `INSERT ... VALUES (?, ?), (?, ?), ...` per batch.
      def copy_from_lines(rows_var, table, columns, attrs, _label)
        rows_per_batch = [MAX_BOUND_PARAMETERS / columns.size, 1].max
        placeholders = "(#{(['?'] * columns.size).join(', ')})"
        body = [
          %(sql = "INSERT INTO #{table} (#{columns.join(', ')}) VALUES \#{Array.new(batch.size, '#{placeholders}').join(', ')}"),
          "client.execute(sql, batch.flat_map { |row| [#{attrs.map { |a| "row.#{a}" }.join(', ')}] })"
        ].join("\n")
        [Code.block("#{rows_var}.each_slice(#{rows_per_batch}) do |batch|", body), 'nil']
      end

      TRANSACTION = <<~'RUBY'.chomp
        # Runs the block in a transaction and returns its value: COMMIT when the block returns, ROLLBACK when it
        # raises. A nested call becomes a SAVEPOINT. mode: :deferred (default), :immediate or :exclusive.
        def transaction(mode: nil)
          outermost = !@db.transaction_active?
          savepoint = outermost ? nil : "sqlc_sp_#{rand(0xffff_ffff).to_s(16)}"
          @db.execute(outermost ? "BEGIN#{" #{mode.to_s.upcase}" if mode}" : "SAVEPOINT #{savepoint}")
          begin
            result = yield self
            @db.execute(outermost ? 'COMMIT' : "RELEASE SAVEPOINT #{savepoint}")
            result
          rescue Exception # rubocop:disable Lint/RescueException
            @db.execute(outermost ? 'ROLLBACK' : "ROLLBACK TO SAVEPOINT #{savepoint}")
            raise
          end
        end
      RUBY

      private

      def driver_gems = %w[sqlite3]

      def column_mappings
        # Ruby classes as returned by the sqlite3 gem (verified by tests/end2end_sqlite3.rb): booleans are 0/1
        # Integers, blobs are Strings, dates are text.
        @column_mappings ||= [
          mapping('Integer', %w[int integer tinyint smallint mediumint bigint unsignedbigint int2 int8 boolean bool]),
          mapping('String', %w[blob datetime date timestamp time]),
          mapping('String', %w[character varchar varyingcharacter nchar nativecharacter nvarchar text clob],
                  prefix_based: true),
          mapping('Float', %w[real double doubleprecision float decimal numeric], prefix_based: true)
        ]
      end
    end
  end
end
