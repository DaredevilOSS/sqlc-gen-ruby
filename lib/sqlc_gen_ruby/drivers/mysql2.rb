# frozen_string_literal: true

require_relative 'base'

module SqlcGenRuby
  module Drivers
    # MySQL / MariaDB via the `mysql2` gem (prepared statements, closed after use).
    class Mysql2 < Base
      def name = 'Mysql2'

      def module_members
        [
          [CONNECTION_STATE, "module ConnectionState\n  attr_accessor in_transaction: bool\nend"],
          [ISOLATION_LEVELS, ISOLATION_RBS]
        ]
      end

      def class_methods
        [
          [NOT_FOUND, "class NotFound < StandardError\nend"],
          [CONNECT, 'def self.connect: (Hash[untyped, untyped] mysql2_params, ?logger: untyped, **untyped pool_options) -> instance'],
          [INITIALIZE, 'def initialize: (untyped db, ?logger: untyped) -> void'],
          [TRANSACTION, TRANSACTION_RBS]
        ]
      end

      def private_methods
        [[INSTRUMENT, INSTRUMENT_RBS], [WITH_CLIENT, 'def with_client: [T] (String name) { (untyped) -> T } -> T']]
      end

      def prepare_stmt(_stmt_name, const) = "stmt = client.prepare(#{const})"

      def execute_stmt(_stmt_name, _const, has_params, array_rows: false)
        args = []
        args << '*query_params' if has_params
        args << 'as: :array' if array_rows
        args.empty? ? 'stmt.execute' : "stmt.execute(#{args.join(', ')})"
      end

      def closes_statements? = true

      def supports_slice? = true

      # Rows are read by position: mysql2 names unaliased expressions after their text (`count(*)`), sqlc does not.
      def row_data_type = :array

      def quote_identifier(name) = "`#{name.gsub('`', '``')}`"

      def exec_rows_lines(exec, _query) = [exec, 'stmt.affected_rows']

      def exec_last_id_lines(exec, _query) = [exec, 'client.last_id']

      def exec_result_lines(exec) = [exec, 'stmt.affected_rows', 'client.last_id']

      # LOAD DATA LOCAL INFILE from a temporary CSV (the client needs `local_infile: true`, the server
      # `local_infile=1`).
      def copy_from_lines(rows_var, table, columns, values, label)
        write = Code.block("#{rows_var}.each do |row|", "file.write(csv_line([#{values.join(', ')}]))")
        load_data = format(LOAD_DATA, table: table, columns: columns.join(', '))
        [
          "return if #{rows_var}.empty?",
          '',
          Code.block("Tempfile.create(['#{label}', '.csv']) do |file|", "#{write}\nfile.flush\n#{load_data}"),
          'nil'
        ]
      end

      def extra_requires(queries, _ruby_version) = copy_from?(queries) ? %w[tempfile] : []

      def helper_methods(queries)
        return [] unless copy_from?(queries)

        [[CSV_LINE, 'def csv_line: (Array[untyped] values) -> String']]
      end

      CONNECTION_STATE = <<~'RUBY'.chomp
        # State kept on every Mysql2::Client the first time it is used.
        module ConnectionState
          attr_accessor :in_transaction
        end
      RUBY

      INITIALIZE = <<~'RUBY'.chomp
        # db: a ConnectionPool (or anything that responds to #with and yields a Mysql2::Client).
        # logger: optional, anything with #debug (Logger, Rails.logger); logs the name and duration of every query.
        def initialize(db, logger: nil)
          @db = db
          @logger = logger
        end
      RUBY

      CONNECT = <<~'RUBY'.chomp
        # Opens a pool of connections: QuerySql.connect({ database: 'app' }, size: 5, timeout: 5, logger: Logger.new($stdout))
        # (pool_options go to ConnectionPool.new). To share an existing pool use QuerySql.new(pool).
        def self.connect(mysql2_params, logger: nil, **pool_options)
          new(ConnectionPool.new(**pool_options) { Mysql2::Client.new(**mysql2_params) }, logger: logger)
        end
      RUBY

      TRANSACTION = <<~'RUBY'.chomp
        # Runs the block in a transaction on one connection and returns its value: COMMIT when the block returns
        # (also through break / return / throw), ROLLBACK when it raises or the thread is killed. A nested call
        # becomes a SAVEPOINT. Yields self, bound to that connection.
        def transaction(isolation: nil)
          with_client('transaction') do |client|
            outermost = !client.in_transaction
            savepoint = outermost ? nil : "sqlc_sp_#{rand(0xffff_ffff).to_s(16)}"
            if outermost
              client.query("SET TRANSACTION ISOLATION LEVEL #{ISOLATION_LEVELS.fetch(isolation)}") if isolation
              client.query('BEGIN')
              client.in_transaction = true
            else
              client.query("SAVEPOINT #{savepoint}")
            end
            rollback = outermost ? 'ROLLBACK' : "ROLLBACK TO SAVEPOINT #{savepoint}"
            failed = false
            begin
              yield self
            rescue Exception # rubocop:disable Lint/RescueException
              failed = true
              client.query(rollback)
              raise
            ensure
              begin
                unless failed
                  commit = outermost ? 'COMMIT' : "RELEASE SAVEPOINT #{savepoint}"
                  client.query(Thread.current.status == 'aborting' ? rollback : commit)
                end
              ensure
                client.in_transaction = false if outermost
              end
            end
          end
        end
      RUBY

      WITH_CLIENT = <<~'RUBY'.chomp
        def with_client(name)
          instrument(name) do
            @db.with do |client|
              client.extend(ConnectionState) unless client.is_a?(ConnectionState)
              yield client
            end
          end
        end
      RUBY

      # Template of the generated statement (single-quoted heredoc: backslashes are copied verbatim).
      LOAD_DATA = <<~'RUBY'.chomp
        client.query("LOAD DATA LOCAL INFILE '#{client.escape(file.path)}' INTO TABLE %<table>s FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '\"' ESCAPED BY '\\\\' LINES TERMINATED BY '\\n' (%<columns>s)")
      RUBY

      # \N is LOAD DATA's NULL; every other value is enclosed in quotes (an unquoted NULL would also be read as
      # NULL), backslashes are doubled because the statement uses ESCAPED BY '\'.
      CSV_LINE = <<~'RUBY'.chomp
        # Formats one row for LOAD DATA ... FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"' ESCAPED BY '\\'.
        def csv_line(values)
          fields = values.map do |value|
            case value
            when nil then '\N'
            when true then '1'
            when false then '0'
            when Time then value.strftime('%Y-%m-%d %H:%M:%S.%6N')
            else %("#{value.to_s.b.gsub('\\') { '\\\\' }.gsub('"', '""')}")
            end
          end
          "#{fields.join(',')}\n"
        end
      RUBY

      private

      def copy_from?(queries) = queries.any? { |q| q.cmd == ':copyfrom' }

      def driver_gems = %w[mysql2]

      def column_mappings
        # Ruby classes as returned by the mysql2 gem (verified by tests/end2end_mysql2.rb)
        @column_mappings ||= [
          mapping('String', %w[char varchar tinytext text mediumtext longtext json binary varbinary bit tinyblob blob
                               mediumblob longblob]),
          mapping('Integer', %w[bigint int mediumint smallint tinyint year integer]),
          mapping('Float', %w[double float]),
          mapping('BigDecimal', %w[decimal numeric dec fixed]),
          mapping('Date', %w[date]),
          mapping('Time', %w[datetime timestamp time])
        ]
      end
    end
  end
end
