# frozen_string_literal: true

require_relative 'base'

module SqlcGenRuby
  module Drivers
    # Port of Drivers/Mysql2Driver.cs.
    class Mysql2 < Base
      def name = 'Mysql2'

      def init_code
        pool = "ConnectionPool.new(**connection_pool_params) {\n" \
               "#{Code.indent('Mysql2::Client.new(**mysql2_params)')}\n}"
        Code.block('def initialize(connection_pool_params, mysql2_params)', "@db = #{pool}")
      end

      def init_type
        "@db: untyped\n" \
          'def initialize: (Hash[String, String], Hash[String, String]) -> void'
      end

      def prepare_stmt(_func_name, const) = "stmt = client.prepare(#{const})"

      def execute_stmt(_func_name, has_params) = has_params ? 'stmt.execute(*query_params)' : 'stmt.execute'

      def supports_exec_last_id? = true

      private

      def driver_gems = %w[mysql2]

      def column_mappings
        @column_mappings ||= [
          mapping('Array[Integer]', %w[binary bit blob longblob mediumblob tinyblob varbinary]),
          mapping('String', %w[char date datetime decimal longtext mediumtext text time timestamp tinytext
                               varchar json]),
          mapping('Integer', %w[bigint int mediumint smallint tinyint year]),
          mapping('Float', %w[double float])
        ]
      end
    end
  end
end
