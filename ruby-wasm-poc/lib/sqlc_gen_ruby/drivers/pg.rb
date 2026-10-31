# frozen_string_literal: true

require_relative '../code'

module SqlcGenRuby
  module Drivers
    # Port of Drivers/PgDriver.cs. Each *_code / *_type pair mirrors the
    # BuildCode / BuildType of the C# syntax tree nodes.
    class Pg
      include Code

      def name = 'Pg'

      def required_gems = %w[connection_pool pg set]

      COLUMN_TYPES = [
        ['bool', %w[bool boolean]],
        ['Array[Integer]', %w[binary bit bytea blob longblob mediumblob tinyblob varbinary]],
        ['String', %w[char date datetime longtext mediumtext text bpchar time timestamp tinytext varchar json]],
        ['Integer', %w[int2 int4 int8 serial bigserial]],
        ['Float', %w[numeric float4 float8 decimal]]
      ].freeze

      def column_type(column)
        db_type = column.type.name.downcase
        COLUMN_TYPES.each { |ruby, dbs| return ruby if dbs.include?(db_type) }
        raise "Unsupported column type: #{column.type.name}"
      end

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

      def query_text_constant(query)
        counter = 0
        text = query.text.gsub('?') { "$#{counter += 1}" }
        Code.dedent_to_first_line("#{query.name}Sql = %q(#{text})")
      end

      def prepare_stmt(func_name, const)
        body = "client.prepare('#{func_name}', #{const})\n@prepared_statements.add('#{func_name}')"
        Code.block("unless @prepared_statements.include?('#{func_name}')", body)
      end

      def execute_stmt(func_name, has_params)
        "client.exec_prepared('#{func_name}'#{has_params ? ', query_params' : ''})"
      end
    end
  end
end
