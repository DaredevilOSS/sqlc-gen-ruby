# frozen_string_literal: true

require_relative 'base'

module SqlcGenRuby
  module Drivers
    # Port of Drivers/Sqlite3Driver.cs. A single SQLite3::Database is injected, so there is no connection
    # pool, and rows are read by index (the sqlite3 gem returns arrays by default).
    class Sqlite3 < Base
      def name = 'Sqlite3'

      def init_code = Code.block('def initialize(db)', '@db = db')

      def init_type = "@db: untyped\ndef initialize: (untyped) -> void"

      def prepare_stmt(_func_name, const) = "stmt = client.prepare(#{const})"

      def execute_stmt(_func_name, has_params) = has_params ? 'stmt.execute(*query_params)' : 'stmt.execute'

      def pooling_enabled? = false

      def row_data_type = :array

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
