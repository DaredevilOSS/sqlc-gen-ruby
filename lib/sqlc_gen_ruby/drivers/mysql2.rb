# frozen_string_literal: true

require_relative 'base'

module SqlcGenRuby
  module Drivers
    # MySQL / MariaDB via the `mysql2` gem.
    class Mysql2 < Base
      def name = 'Mysql2'

      def module_members
        [
          [CONNECTION_STATE, "module ConnectionState\n  attr_accessor in_transaction: bool\n" \
                             "  def query: (*untyped) -> untyped\n  def query_running?: () -> bool\nend"],
          [TRANSACTION_CONNECTION, TRANSACTION_CONNECTION_RBS],
          [ISOLATION_LEVELS, ISOLATION_RBS]
        ]
      end

      def class_methods(ruby_version)
        transaction = legacy_transaction_template(
          TRANSACTION, ruby_version,
          "::Thread.current.status == 'aborting' ? rollback : commit",
          "::Thread.current.status == 'aborting' || (!completed && timeout_exits_with_throw?) ? rollback : commit"
        )
        [
          [NOT_FOUND, "class NotFound < ::StandardError\nend"],
          [CONNECT, 'def self.connect: (::Hash[untyped, untyped] mysql2_params, ?logger: untyped, **untyped pool_options) -> instance'],
          [INITIALIZE, 'def initialize: (untyped db, ?logger: untyped) -> void'],
          [transaction, TRANSACTION_RBS]
        ]
      end

      def private_methods(ruby_version)
        [
          [INSTRUMENT, INSTRUMENT_RBS],
          [WITH_CLIENT, 'def with_client: [T] (::String name) { (untyped) -> T } -> T'],
          bound_to_method('@db'),
          *timeout_exit_methods(ruby_version)
        ]
      end

      def prepare_stmt(_stmt_name, _const) = nil

      def execute_stmt(_stmt_name, const, has_params, array_rows: false)
        sql = "bind_params(client, #{const}, #{has_params ? 'query_params' : '[]'})"
        sql = "client.query(#{sql}"
        sql += ', as: :array' if array_rows
        "#{sql})"
      end

      def closes_statements? = false

      def supports_slice? = true

      # Rows are read by position: mysql2 names unaliased expressions after their text (`count(*)`), sqlc does not.
      def row_data_type = :array

      def quote_identifier(name) = "`#{name.gsub('`', '``')}`"

      IDENTIFIER = /`(?:[^`]|``)*`|[^\s`.,()]+/

      # sqlc lowercases MySQL identifiers, but table names are case-sensitive on Linux: LOAD DATA names the table
      # and columns as the INSERT writes them (`MixedCase`).
      def copy_target(sql, table, columns)
        target = sql.gsub(%r{--[^\n]*|/\*.*?\*/}m, ' ')
                    .match(/\bINTO\s+(#{IDENTIFIER}(?:\s*\.\s*#{IDENTIFIER})?)\s*\(([^)]*)\)/i)
        return super unless target

        *schema, name = target[1].scan(IDENTIFIER).map { |i| unquote_identifier(i) }
        return super unless name.casecmp?(table.name)

        written = target[2].scan(IDENTIFIER).to_h { |c| [unquote_identifier(c).downcase, unquote_identifier(c)] }
        [[*schema, name].map { |n| quote_identifier(n) }.join('.'),
         columns.map { |c| quote_identifier(written.fetch(c.downcase, c)) }]
      end

      def unquote_identifier(identifier) = identifier.start_with?('`') ? identifier[1...-1].gsub('``', '`') : identifier

      def exec_rows_lines(exec, _query) = [exec, 'client.affected_rows']

      def exec_last_id_lines(exec, _query) = [exec, 'client.last_id']

      def exec_result_lines(exec, _query) = [exec, 'client.affected_rows', 'client.last_id']

      # LOAD DATA LOCAL INFILE from a temporary CSV (the client needs `local_infile: true`, the server
      # `local_infile=1`).
      def copy_from_lines(rows_var, table, columns, values, label, query_name:, sources:, verb:, tail:)
        unless tail.empty? && verb.match?(/\A(INSERT|REPLACE)\b/)
          raise ArgumentError, "#{query_name}: :copyfrom (LOAD DATA) takes INSERT [IGNORE] / REPLACE ... VALUES (...), " \
                               'without ON DUPLICATE KEY UPDATE'
        end

        write = Code.block("#{rows_var}.each do |row|", "file.write(csv_line([#{values.join(', ')}]))")
        load_data = format(LOAD_DATA, table: table, **load_columns(columns, sources),
                                      mode: load_mode(verb), strict: verb.split.include?('IGNORE') ? ', strict: false' : '')
        [
          Code.block("::Tempfile.create(['#{label}', '.csv']) do |file|", "#{write}\nfile.flush\n#{load_data} if file.pos.positive?"),
          'nil'
        ]
      end

      # INSERT IGNORE skips duplicates and adjusts invalid values (with warnings); REPLACE replaces duplicates.
      def load_mode(verb)
        if verb.start_with?('REPLACE') then 'REPLACE '
        elsif verb.split.include?('IGNORE') then 'IGNORE '
        else ''
        end
      end

      # The file is read as binary (binary columns keep every byte); JSON columns need text: they are loaded through
      # a user variable converted to utf8mb4.
      def load_columns(columns, sources)
        json = columns.each_index.select { |i| normalize_type(sources[i].type.name) == 'json' }
        list = columns.each_with_index.map { |c, i| json.include?(i) ? "@sqlc_v#{i}" : c }
        set = json.map { |i| "#{columns[i]} = CONVERT(@sqlc_v#{i} USING utf8mb4)" }
        { columns: list.join(', '), set: set.empty? ? '' : " SET #{set.join(', ')}" }
      end

      def prepares_batch_rows? = false

      def extra_requires(queries, _ruby_version) = %w[bigdecimal date] + (copy_from?(queries) ? %w[tempfile] : [])

      def extra_gems(_queries) = %w[bigdecimal date]

      def helper_methods(queries)
      helpers = [[QUOTE, 'def quote: (untyped client, untyped value) -> ::String'],
                 [BIND_PARAMS, 'def bind_params: (untyped client, ::String sql, ::Array[untyped] params) -> ::String']]
        helpers.concat([[CSV_LINE, 'def csv_line: (::Array[untyped] values) -> ::String'],
                        [LOAD_DATA_HELPER, 'def load_data: (untyped client, ::String sql, ?strict: bool) -> void']]) if copy_from?(queries)
        helpers
      end

      CONNECTION_STATE = <<~'RUBY'.chomp
        # State kept on every Mysql2::Client the first time it is used.
        module ConnectionState
          attr_accessor :in_transaction

          # Stays true when a Thread#kill interrupts the query (it skips rescue): see #with_client.
          def query(...)
            @query_running = true
            result = super
            @query_running = false
            result
          rescue ::Exception # rubocop:disable Lint/RescueException
            @query_running = false
            raise
          end

          def query_running? = @query_running == true
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
          new(::ConnectionPool.new(**pool_options) { ::Mysql2::Client.new(**mysql2_params) }, logger: logger)
        end
      RUBY

      TRANSACTION = <<~'RUBY'.chomp
        # Runs the block in a transaction on one connection and returns its value: COMMIT when the block returns
        # (also through break / return / throw), ROLLBACK when it raises or the thread is killed. A nested call
        # becomes a SAVEPOINT. Yields a copy of self whose queries run in the transaction, also from other fibers and
        # threads (Enumerator, Async tasks); it raises TransactionEnded when used after the transaction.
        def transaction(isolation: nil)
          raise ::ArgumentError, "unknown isolation level: #{isolation.inspect}" unless isolation.nil? || ISOLATION_LEVELS.key?(isolation)

          with_client('transaction') do |client|
            outermost = !client.in_transaction
            raise ::ArgumentError, 'isolation: cannot be set on a nested transaction' if isolation && !outermost

            savepoint = outermost ? nil : "sqlc_sp_#{rand(0xffff_ffff).to_s(16)}"
            level = "SET TRANSACTION ISOLATION LEVEL #{ISOLATION_LEVELS.fetch(isolation)}" if isolation
            rollback = outermost ? 'ROLLBACK' : "ROLLBACK TO SAVEPOINT #{savepoint}"
            # Timeout / Thread#raise / Thread#kill wait while BEGIN, COMMIT and ROLLBACK run and only interrupt the
            # block: the connection never goes back to the pool inside a transaction.
            bound = TransactionConnection.new(client) unless @db.is_a?(TransactionConnection)
            ::Thread.handle_interrupt(::Object => :never) do
              started = false
              failed = false
              begin
                if outermost
                  client.in_transaction = true
                  client.query(level) if level
                  client.query('BEGIN')
                else
                  client.query("SAVEPOINT #{savepoint}")
                end
                started = true
                ::Thread.handle_interrupt(::Object => :immediate) do
                  bound ? yield(bound_to(bound)) : @db.unlocked { yield self }
                end
              rescue ::Exception => e # rubocop:disable Lint/RescueException
                failed = true
                bound&.close
                begin
                  client.query(rollback) if started || outermost
                rescue ::Mysql2::Error
                  # a deadlock / lock wait timeout already rolled back the transaction: its savepoints are gone;
                  # an interrupted query closed the connection: the server rolls back
                  raise unless e.is_a?(::Mysql2::Error) || client.closed?
                end
                raise
              ensure
                bound&.close
                begin
                  unless failed
                    if ::Thread.current.status == 'aborting' && client.query_running?
                      # Thread#kill interrupted a query: the client still waits for its result and cannot send
                      # ROLLBACK. Closing it makes the server roll back; #with_client discards it.
                      client.close
                    else
                      commit = outermost ? 'COMMIT' : "RELEASE SAVEPOINT #{savepoint}"
                      begin
                        client.query(::Thread.current.status == 'aborting' ? rollback : commit)
                      rescue ::Exception # rubocop:disable Lint/RescueException
                        # COMMIT did not run: roll back instead of leaving the transaction open (a closed client is
                        # discarded and the server rolls back)
                        begin
                          client.query('ROLLBACK') if outermost && !client.closed?
                        rescue ::Mysql2::Error
                          nil
                        end
                        raise
                      end
                    end
                  end
                ensure
                  client.in_transaction = false if outermost
                end
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
              begin
                yield client
              rescue ::Exception # rubocop:disable Lint/RescueException
                # a connection closed by the server (restart, KILL, wait_timeout) or by mysql2 when a running query
                # was interrupted (Async task stopped, Thread#raise) is replaced by the pool
                @db.discard_current_connection if client.closed? && @db.respond_to?(:discard_current_connection)
                raise
              ensure
                # Thread#kill skips rescue: a query it interrupted leaves the client waiting for a result nobody reads
                # (every later query raises) and its transaction open. Closing it makes the server roll back once the
                # statement ends, and the pool replaces it.
                if ::Thread.current.status == 'aborting' && (client.query_running? || client.closed?)
                  client.close
                  @db.discard_current_connection if @db.respond_to?(:discard_current_connection)
                end
              end
            end
          end
        end
      RUBY

      # Template of the generated statement (single-quoted heredoc: backslashes are copied verbatim).
      LOAD_DATA = <<~'RUBY'.chomp
        load_data(client, "LOAD DATA LOCAL INFILE '#{client.escape(file.path)}' %<mode>sINTO TABLE %<table>s CHARACTER SET binary FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '\"' ESCAPED BY '\\\\' LINES TERMINATED BY '\\n' (%<columns>s)%<set>s"%<strict>s)
      RUBY

      # LOAD DATA LOCAL skips duplicate keys and converts invalid values with a warning instead of failing.
      LOAD_DATA_HELPER = <<~'RUBY'.chomp
        # Runs LOAD DATA in a transaction (a savepoint inside #transaction): all rows or none, and (strict) an error
        # instead of the warnings LOAD DATA LOCAL gives for duplicate keys and invalid values.
        def load_data(client, sql, strict: true)
          outermost = !client.in_transaction
          client.query(outermost ? 'BEGIN' : 'SAVEPOINT sqlc_copy')
          done = false
          begin
            client.query(sql)
            if strict && !client.warning_count.zero?
              warnings = client.query('SHOW WARNINGS', as: :array).reject { |level, *| level == 'Note' }
              raise ::Mysql2::Error, "LOAD DATA: #{warnings.map { |w| w[2] }.join('; ')}" unless warnings.empty?
            end
            done = true
          ensure
            if outermost
              client.query(done ? 'COMMIT' : 'ROLLBACK')
            else
              client.query(done ? 'RELEASE SAVEPOINT sqlc_copy' : 'ROLLBACK TO SAVEPOINT sqlc_copy')
            end
          end
        end
      RUBY

      # \N is LOAD DATA's NULL; every other value is enclosed in quotes (an unquoted NULL would also be read as
      # NULL), backslashes are doubled because the statement uses ESCAPED BY '\'. Ctrl-Z is written as \Z: the client
      # library reads the file in text mode on Windows, where a raw Ctrl-Z ends it.
      CSV_LINE = <<~'RUBY'.chomp
        # Formats one row for LOAD DATA ... FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"' ESCAPED BY '\\'.
        def csv_line(values)
          fields = values.map do |value|
            case value
            when nil then '\N'
            when true then '1'
            when false then '0'
            when ::Time then value.strftime('%Y-%m-%d %H:%M:%S.%6N')
            else %("#{value.to_s.b.gsub('\\') { '\\\\' }.gsub('"', '""').gsub("\x1A") { '\Z' }}")
            end
          end
          "#{fields.join(',')}\n"
        end
      RUBY

      QUOTE = <<~'RUBY'.chomp
        def quote(client, value)
          case value
          when ::NilClass then 'NULL'
          when ::Symbol then quote(client, value.to_s)
          when ::TrueClass then 'TRUE'
          when ::FalseClass then 'FALSE'
          when ::Integer then value.to_s
          when ::Float
            raise ::ArgumentError, 'cannot bind a non-finite Float to MySQL' unless value.finite?

            value.to_s
          when ::BigDecimal
            raise ::ArgumentError, 'cannot bind a non-finite BigDecimal to MySQL' unless value.finite?

            value.to_s('F')
          when ::DateTime, ::Time
            "'#{value.strftime('%Y-%m-%d %H:%M:%S.%6N')}'"
          when ::Date
            "'#{value.strftime('%Y-%m-%d')}'"
          when ::String
            if value.encoding == ::Encoding::BINARY || !value.valid_encoding?
              "X'#{value.unpack1('H*')}'"
            else
              "'#{client.escape(value)}'"
            end
          else
            raise ::TypeError, "cannot bind #{value.class} to MySQL"
          end
        end
      RUBY

      BIND_PARAMS = <<~'RUBY'.chomp
        def bind_params(client, sql, params)
          output = +''
          index = 0
          parameter = 0
          while index < sql.length
            char = sql[index]
            if ["'", '"', '`'].include?(char)
              quote_char = char
              start = index
              index += 1
              while index < sql.length
                if sql[index] == '\\'
                  index += 2
                elsif sql[index] == quote_char
                  if sql[index + 1] == quote_char
                    index += 2
                  else
                    index += 1
                    break
                  end
                else
                  index += 1
                end
              end
              output << sql[start...index]
            elsif sql[index, 2] == '--' && (sql[index + 2].nil? || sql[index + 2].match?(/\s/))
              finish = sql.index("\n", index) || sql.length
              output << sql[index...finish]
              index = finish
            elsif char == '#'
              finish = sql.index("\n", index) || sql.length
              output << sql[index...finish]
              index = finish
            elsif sql[index, 2] == '/*'
              finish = sql.index('*/', index + 2)
              finish = finish ? finish + 2 : sql.length
              output << sql[index...finish]
              index = finish
            elsif char == '?'
              raise ::ArgumentError, 'more MySQL placeholders than parameters' if parameter >= params.length

              output << quote(client, params[parameter])
              parameter += 1
              index += 1
            else
              output << char
              index += 1
            end
          end
          raise ::ArgumentError, 'fewer MySQL placeholders than parameters' unless parameter == params.length

          output
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
