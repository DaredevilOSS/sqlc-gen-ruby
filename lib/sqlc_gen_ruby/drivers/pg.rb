# frozen_string_literal: true

require_relative 'base'

module SqlcGenRuby
  module Drivers
    # Port of Drivers/PgDriver.cs. Each *_code / *_type pair mirrors the
    # BuildCode / BuildType of the C# syntax tree nodes.
    class Pg < Base
      def name = 'Pg'

      def init_code
        pool_body = [
          'client = PG.connect(**pg_params)',
          'type_map = PG::BasicTypeMapForResults.new client',
          'type_map.default_type_map = PG::TypeMapAllStrings.new # uuid, enums, money, ... come back as Strings',
          'client.type_map_for_results = type_map',
          'client.type_map_for_queries = PG::BasicTypeMapForQueries.new client',
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

      # PG::Connection#transaction commits when the block returns and rolls back when it raises.
      def transaction_code
        Code.block('def transaction', Code.block('@db.with do |client|', Code.block('client.transaction do', 'yield self')))
      end

      def prepare_stmt(func_name, const)
        body = "client.prepare('#{func_name}', #{const})\n@prepared_statements.add('#{func_name}')"
        Code.block("unless @prepared_statements.include?('#{func_name}')", body)
      end

      def execute_stmt(func_name, has_params, array_rows: false)
        call = "client.exec_prepared('#{func_name}'#{has_params ? ', query_params' : ''})"
        array_rows ? "#{call}.values" : call
      end

      def exec_rows_lines(exec) = ["result = #{exec}", 'return result.cmd_tuples']

      # Relies on a user-written `RETURNING <id>`.
      def exec_last_id_lines(exec, query)
        if query.columns.empty?
          raise ArgumentError, "#{query.name}: :execlastid on PostgreSQL needs a RETURNING clause"
        end

        ["result = #{exec}", "return result.first['#{query.columns.first.name}']"]
      end

      # COPY ... FROM STDIN, one row at a time through the pg gem's CopyRow encoder.
      def copy_from_lines(query, table, columns)
        args = Code.snake_case("#{query.name}Args")
        put = Code.block("#{args}.each do |item|",
                         "client.put_copy_data([#{columns.map { |c| "item.#{c}" }.join(', ')}])")
        [
          'encoder = PG::TextEncoder::CopyRow.new(type_map: client.type_map_for_queries)',
          Code.block("client.copy_data('COPY #{table} (#{columns.join(', ')}) FROM STDIN', encoder) do", put)
        ]
      end

      private

      def driver_gems = %w[pg set]

      def column_mappings
        # Ruby classes as returned by the pg gem with PG::BasicTypeMapForResults (verified by tests/end2end_pg.rb);
        # types without a decoder (uuid, money, interval, enums, ...) come back as Strings.
        @column_mappings ||= [
          mapping('bool', %w[bool boolean]),
          mapping('String', %w[char bpchar varchar text time uuid money macaddr macaddr8 interval xml name citext
                               bit varbit bytea tinytext mediumtext longtext tinyblob blob mediumblob longblob
                               binary varbinary]),
          mapping('Integer', %w[int2 int4 int8 serial bigserial integer smallint bigint int smallserial]),
          mapping('Float', %w[float4 float8 real double]),
          mapping('BigDecimal', %w[numeric decimal]),
          mapping('Date', %w[date]),
          mapping('Time', %w[timestamp timestamptz datetime]),
          mapping('IPAddr', %w[inet cidr]),
          mapping('untyped', %w[json jsonb])
        ]
      end
    end
  end
end
