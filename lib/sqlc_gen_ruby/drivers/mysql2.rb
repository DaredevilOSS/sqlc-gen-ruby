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

      # mysql2 has no transaction helper: BEGIN / COMMIT / ROLLBACK on the (reentrantly pooled) connection.
      def transaction_code
        guarded = [
          'begin',
          Code.indent("result = yield self\nclient.query('COMMIT')\nresult"),
          'rescue Exception',
          Code.indent("client.query('ROLLBACK')\nraise"),
          'end'
        ].join("\n")
        Code.block('def transaction', Code.block('@db.with do |client|', "client.query('BEGIN')\n#{guarded}"))
      end

      def prepare_stmt(_func_name, const) = "stmt = client.prepare(#{const})"

      def execute_stmt(_func_name, has_params, array_rows: false)
        args = []
        args << '*query_params' if has_params
        args << 'as: :array' if array_rows
        args.empty? ? 'stmt.execute' : "stmt.execute(#{args.join(', ')})"
      end

      def closes_statements? = true

      def supports_slice? = true

      def exec_rows_lines(exec) = [exec, 'return stmt.affected_rows']

      def exec_last_id_lines(exec, _query) = [exec, 'return client.last_id']

      # LOAD DATA LOCAL INFILE from a temporary CSV (the client needs `local_infile: true`, the server
      # `local_infile=1`).
      def copy_from_lines(query, table, columns)
        args = Code.snake_case("#{query.name}Args")
        write = Code.block("#{args}.each do |item|",
                           "file.write(csv_line([#{columns.map { |c| "item.#{c}" }.join(', ')}]))")
        load_data = format(LOAD_DATA, table: table, columns: columns.join(', '))
        [
          "return if #{args}.empty?",
          Code.block("Tempfile.create(['#{Code.snake_case(query.name)}', '.csv']) do |file|",
                     "#{write}\nfile.flush\n#{load_data}")
        ]
      end

      def extra_requires(queries) = copy_from?(queries) ? %w[csv tempfile] : []

      def extra_gems(queries) = copy_from?(queries) ? %w[csv] : []

      def helper_methods(queries)
        return [] unless copy_from?(queries)

        [[CSV_LINE_CODE, 'def csv_line: (Array[untyped]) -> String']]
      end

      # Template of the generated statement (single-quoted heredoc: backslashes are copied verbatim).
      LOAD_DATA = <<~'RUBY'.chomp
        client.query("LOAD DATA LOCAL INFILE '#{client.escape(file.path)}' INTO TABLE %<table>s FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '\"' ESCAPED BY '\\\\' LINES TERMINATED BY '\\n' (%<columns>s)")
      RUBY

      # \N is LOAD DATA's NULL; backslashes are doubled because the statement uses ESCAPED BY '\'.
      CSV_LINE_CODE = [
        'def csv_line(values)',
        Code.indent(
          [
            'fields = values.map do |value|',
            Code.indent(
              [
                'case value',
                "when nil then '\\N'",
                "when true then '1'",
                "when false then '0'",
                "when Time then value.strftime('%Y-%m-%d %H:%M:%S.%6N')",
                "else value.to_s.gsub('\\\\') { '\\\\\\\\' }",
                'end'
              ].join("\n")
            ),
            'end',
            'CSV.generate_line(fields)'
          ].join("\n")
        ),
        'end'
      ].join("\n")

      private

      def copy_from?(queries) = queries.any? { |q| q.cmd == ':copyfrom' }

      def driver_gems = %w[mysql2]

      def column_mappings
        @column_mappings ||= [
          mapping('Array[Integer]', %w[binary bit blob longblob mediumblob tinyblob varbinary]),
          mapping('String', %w[char date datetime decimal longtext mediumtext text time timestamp tinytext
                               varchar json]),
          mapping('Integer', %w[bigint int mediumint smallint tinyint year integer]),
          mapping('Float', %w[double float])
        ]
      end
    end
  end
end
