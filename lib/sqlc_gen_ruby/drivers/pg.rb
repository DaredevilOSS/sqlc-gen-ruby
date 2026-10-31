# frozen_string_literal: true

require_relative 'base'

module SqlcGenRuby
  module Drivers
    # Port of Drivers/PgDriver.cs.
    class Pg < Base
      def name = 'Pg'

      def init_code
        pool_body = [
          'client = PG.connect(**pg_params)',
          'client.type_map_for_results = PG::BasicTypeMapForResults.new client',
          'client'
        ].join("\n")
        pool = "ConnectionPool.new(**connection_pool_params) {\n#{Code.indent(pool_body)}\n}"
        body = ["@db = #{pool}", '@prepared_statements = Set[]'].join("\n")
        Code.block('def initialize(connection_pool_params, pg_params)', body)
      end

      def init_type
        "@db: untyped\n@prepared_statements: Set[String]\n" \
          'def initialize: (Hash[String, String], Hash[String, String]) -> void'
      end

      # sqlc emits `?` placeholders; PostgreSQL wants $1, $2, ...
      def query_text(query)
        counter = 0
        query.text.gsub('?') { "$#{counter += 1}" }
      end

      def prepare_stmt(func_name, const)
        body = "client.prepare('#{func_name}', #{const})\n@prepared_statements.add('#{func_name}')"
        Code.block("unless @prepared_statements.include?('#{func_name}')", body)
      end

      def execute_stmt(func_name, has_params)
        "client.exec_prepared('#{func_name}'#{has_params ? ', query_params' : ''})"
      end

      private

      def driver_gems = %w[pg set]

      def column_mappings
        @column_mappings ||= [
          mapping('bool', %w[bool boolean]),
          mapping('Array[Integer]', %w[binary bit bytea blob longblob mediumblob tinyblob varbinary]),
          mapping('String', %w[char date datetime longtext mediumtext text bpchar time timestamp tinytext
                               varchar json]),
          mapping('Integer', %w[int2 int4 int8 serial bigserial]),
          mapping('Float', %w[numeric float4 float8 decimal])
        ]
      end
    end
  end
end
