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

      def module_members = [[CONNECTION_LOCK, CONNECTION_LOCK_RBS]]

      def extra_requires(_queries, _ruby_version) = %w[monitor]

      def helper_methods(queries)
        return [] unless queries.any? { |q| q.cmd == ':copyfrom' }

        [[ATOMICALLY, 'def atomically: (untyped client) { () -> void } -> void']]
      end

      def class_methods(ruby_version)
        transaction = legacy_transaction_template(
          TRANSACTION, ruby_version,
          "Thread.current.status == 'aborting' ? rollback : commit",
          "Thread.current.status == 'aborting' || (!completed && timeout_exits_with_throw?) ? rollback : commit"
        )
        [
          [NOT_FOUND, "class NotFound < StandardError\nend"],
          [INITIALIZE, 'def initialize: (untyped db, ?logger: untyped) -> void'],
          [transaction, "def transaction: [T] (?mode: (:deferred | :immediate | :exclusive)?) { (self) -> T } -> T"]
        ]
      end

      def private_methods(ruby_version)
        [
          [INSTRUMENT, INSTRUMENT_RBS],
          ["def with_client(name, &block)\n  instrument(name) { @lock.synchronize { block.call(@db) } }\nend",
           'def with_client: [T] (String name) { (untyped) -> T } -> T'],
          [EXECUTE_STATEMENT, 'def execute_statement: (untyped stmt, *untyped params) -> untyped'],
          *timeout_exit_methods(ruby_version)
        ]
      end

      def prepare_stmt(_stmt_name, const) = "stmt = client.prepare(#{const})"

      def execute_stmt(_stmt_name, _const, has_params, array_rows: false)
        has_params ? 'execute_statement(stmt, *query_params)' : 'execute_statement(stmt)'
      end

      # Statement#execute, but rows are always Arrays (they are read by position), also when the database was
      # opened with results_as_hash: true.
      EXECUTE_STATEMENT = <<~'RUBY'.chomp
        def execute_statement(stmt, *params)
          stmt.reset! if stmt.active? || stmt.done?
          stmt.bind_params(*params) unless params.empty?
          result = SQLite3::ResultSet.new(@db, stmt)
          stmt.step if stmt.column_count.zero?
          result
        end
      RUBY

      def row_data_type = :array

      def closes_statements? = true

      def supports_slice? = true

      # sqlc misses parameters in some SQLite clauses (ON CONFLICT ... DO UPDATE SET): it leaves sqlc.arg(...) in the
      # SQL or reports fewer parameters than there are placeholders, and the method would bind too few values.
      def check_placeholders(query)
        hint = 'sqlc does not see parameters there (e.g. in SQLite ON CONFLICT ... DO UPDATE SET); ' \
               'use excluded.<column> or move the value into VALUES'
        if /\bsqlc\s*\.\s*(?:arg|narg|slice|embed)\s*\(/i.match?(without_literals(query.text))
          raise ArgumentError, "#{query.name}: sqlc left a sqlc.* macro in the SQL: #{hint}"
        end

        occurrences = placeholder_occurrences(query.text)
        referenced = occurrences.filter_map { |kind, number,| number if kind == :numbered }
        slices = occurrences.filter_map { |kind, name,| name if kind == :slice }
        expected = query.params.count do |source|
          !referenced.include?(source.number) && !(source.column.is_sqlc_slice && slices.include?(source.column.name))
        end
        unreported = [occurrences.count { |kind,| kind == :positional } - expected, 0].max +
                     (referenced.uniq - query.params.map(&:number)).size
        return if unreported.zero?

        raise ArgumentError, "#{query.name}: the SQL has #{unreported} placeholder(s) that sqlc reported no parameter for: #{hint}"
      end

      def without_literals(sql)
        sql.gsub(/'(?:[^']|'')*'|"(?:[^"]|"")*"|`(?:[^`]|``)*`|\[[^\]]*\]|--[^\n]*|\/\*.*?\*\//m, ' ')
      end

      def query_text_constant(query)
        check_placeholders(query)
        super
      end

      def query_text(query)
        replacements = placeholder_occurrences(query.text).filter_map do |kind, number, first, last|
          [first, last] if kind == :numbered
        end
        return query.text if replacements.empty?

        replacements.reverse_each.reduce(query.text.dup) { |sql, (first, last)| sql[0...first] + '?' + sql[last..] }
      end

      def query_params(query, params, value_prefix: '')
        occurrences = placeholder_occurrences(query.text)
        unless occurrences.any? { |kind,| kind == :numbered || kind == :slice }
          return super(query, params, value_prefix: value_prefix)
        end

        by_number = query.params.zip(params).to_h { |source, param| [source.number, param] }
        referenced = occurrences.filter_map { |kind, number,| number if kind == :numbered }
        slices = occurrences.filter_map { |kind, name,| name if kind == :slice }
        positional = query.params.each_with_index.filter_map do |source, index|
          by_number[source.number] unless referenced.include?(source.number) ||
                                          (source.column.is_sqlc_slice && slices.include?(source.column.name))
        end
        positional_index = 0
        ordered = occurrences.map do |kind, value,|
          case kind
          when :slice
            query.params.each_with_index.find { |source, _| source.column.is_sqlc_slice && source.column.name == value }
                       .then { |_, index| params[index] }
          when :numbered then by_number.fetch(value)
          when :positional
            param = positional.fetch(positional_index)
            positional_index += 1
            param
          end
        end
        expressions = ordered.map do |param|
          value = "#{value_prefix}#{param.name}"
          param.slice ? "*#{value}" : encode_param(value, param.column)
        end
        "query_params = [#{Code.comma_join(expressions)}]"
      end

      def placeholder_occurrences(sql)
        occurrences = []
        index = 0
        while index < sql.length
          if (slice = /\A\/\*SLICE:([A-Za-z_]\w*)\*\/\?/.match(sql[index..]))
            occurrences << [:slice, slice[1], index, index + slice[0].length]
            index += slice[0].length
          elsif sql[index..].start_with?('--')
            index = (sql.index("\n", index) || sql.length)
          elsif sql[index..].start_with?('/*')
            index = (sql.index('*/', index + 2) || sql.length - 2) + 2
          elsif %w[' " `].include?(sql[index])
            quote = sql[index]
            index += 1
            while index < sql.length
              if sql[index] == quote
                if sql[index + 1] == quote
                  index += 2
                else
                  index += 1
                  break
                end
              else
                index += 1
              end
            end
          elsif sql[index] == '['
            index = (sql.index(']', index + 1) || sql.length - 1) + 1
          elsif sql[index] == '?'
            finish = index + 1
            finish += 1 while finish < sql.length && sql[finish].match?(/\d/)
            kind = finish == index + 1 ? :positional : :numbered
            number = kind == :numbered ? sql[(index + 1)...finish].to_i : nil
            occurrences << [kind, number, index, finish]
            index = finish
          else
            index += 1
          end
        end
        occurrences
      end

      # sqlite3 only runs a statement eagerly when it has no result columns: one with RETURNING is stepped to the end.
      def exec_lines(exec, query) = [query.columns.empty? ? exec : "#{exec}.to_a", 'nil']

      def exec_rows_lines(exec, query) = [query.columns.empty? ? exec : "#{exec}.to_a", 'client.changes']

      def exec_result_lines(exec) = [exec, 'client.changes', 'client.last_insert_row_id']

      # Relies on a user-written `RETURNING <id>`.
      def exec_last_id_lines(exec, query)
        if query.columns.empty?
          raise ArgumentError, "#{query.name}: :execlastid on SQLite needs a RETURNING clause"
        end

        ["result = #{exec}", 'row = result.first', 'row && row[0]']
      end

      # One multi-row `INSERT ... VALUES (?, ?), (?, ?), ...` per batch.
      # The conflict clause is kept: INSERT OR REPLACE / OR IGNORE, REPLACE, ON CONFLICT ... DO ... (without parameters).
      def copy_from_lines(rows_var, table, columns, values, _label, query_name:, sources:, verb:, tail:)
        raise ArgumentError, "#{query_name}: :copyfrom takes no parameters after VALUES (...)" if tail.include?('?')

        rows_per_batch = [MAX_BOUND_PARAMETERS / columns.size, 1].max
        placeholders = "(#{(['?'] * columns.size).join(', ')})"
        tail = tail.empty? ? '' : " #{tail.gsub('\\') { '\\\\' }.gsub('#', '\\#')}"
        body = [
          "sql = %(#{verb} INTO #{table} (#{columns.join(', ')}) VALUES \#{Array.new(batch.size, '#{placeholders}').join(', ')}#{tail})",
          "client.execute(sql, batch.flat_map { |row| [#{values.join(', ')}] })"
        ].join("\n")
        [Code.block('atomically(client) do', Code.block("#{rows_var}.each_slice(#{rows_per_batch}) do |batch|", body)), 'nil']
      end

      INITIALIZE = <<~'RUBY'.chomp
        # db: a SQLite3::Database (a single connection; threads and fibers using it take turns).
        # logger: optional, anything with #debug (Logger, Rails.logger); logs the name and duration of every query.
        def initialize(db, logger: nil)
          @db = db
          @logger = logger
          @lock = ConnectionLock.for(db)
        end
      RUBY

      TRANSACTION = <<~'RUBY'.chomp
        # Runs the block in a transaction and returns its value: COMMIT when the block returns (also through
        # break / return / throw), ROLLBACK when it raises or the thread is killed. A nested call becomes a
        # SAVEPOINT. mode: :deferred (default), :immediate or :exclusive. Other threads / fibers using the same
        # database wait until it ends.
        def transaction(mode: nil)
          raise ArgumentError, "unknown transaction mode: #{mode.inspect}" unless [nil, *TRANSACTION_MODES].include?(mode)

          instrument('transaction') do
            @lock.synchronize do
              outermost = !@db.transaction_active?
              raise ArgumentError, 'mode: cannot be set on a nested transaction' if mode && !outermost

              savepoint = outermost ? nil : "sqlc_sp_#{rand(0xffff_ffff).to_s(16)}"
              @db.execute(outermost ? "BEGIN#{" #{mode.to_s.upcase}" if mode}" : "SAVEPOINT #{savepoint}")
              rollback = outermost ? 'ROLLBACK' : "ROLLBACK TO SAVEPOINT #{savepoint}"
              failed = false
              begin
                yield self
              rescue Exception # rubocop:disable Lint/RescueException
                failed = true
                @db.execute(rollback) if @db.transaction_active? # ON CONFLICT ROLLBACK already ended it
                raise
              ensure
                unless failed
                  commit = outermost ? 'COMMIT' : "RELEASE SAVEPOINT #{savepoint}"
                  @db.execute(Thread.current.status == 'aborting' ? rollback : commit)
                end
              end
            end
          end
        end
      RUBY

      # A SQLite3::Database runs one transaction at a time: every query class using it shares one lock, kept on the
      # database (a Monitor, owned per Fiber, so a transaction's own queries re-enter it).
      CONNECTION_LOCK = <<~'RUBY'.chomp
        module ConnectionLock
          MUTEX = Mutex.new

          def self.for(db)
            MUTEX.synchronize do
              db.extend(self) unless db.is_a?(self)
              db.sqlc_lock
            end
          end

          def sqlc_lock = @sqlc_lock ||= Monitor.new
        end

        TRANSACTION_MODES = %i[deferred immediate exclusive].freeze
      RUBY

      CONNECTION_LOCK_RBS = <<~'RBS'.chomp
        module ConnectionLock
          MUTEX: Thread::Mutex
          @sqlc_lock: Monitor

          def self.for: (untyped db) -> Monitor
          def sqlc_lock: () -> Monitor
        end

        TRANSACTION_MODES: Array[Symbol]
      RBS

      # All rows or none: a SAVEPOINT is a transaction of its own outside #transaction.
      ATOMICALLY = <<~'RUBY'.chomp
        def atomically(client)
          client.execute('SAVEPOINT sqlc_copy')
          done = false
          begin
            yield
            done = true
          ensure
            client.execute('ROLLBACK TO SAVEPOINT sqlc_copy') unless done
            client.execute('RELEASE SAVEPOINT sqlc_copy')
          end
        end
      RUBY

      private

      # VARCHAR(255) -> varchar, UNSIGNED BIG INT -> unsignedbigint
      def normalize_type(type_name) = super.sub(/\(.*\z/m, '').delete(" \t\n")

      # https://www.sqlite.org/datatype3.html#determination_of_column_affinity
      def affinity_type(db_type)
        case db_type
        when /int/ then 'Integer'
        when /char|clob|text/, /blob/, '' then 'String'
        when /real|floa|doub/ then 'Float'
        else 'Float' # NUMERIC affinity, see decimal / numeric above
        end
      end

      def driver_gems = %w[sqlite3]

      def column_mappings
        # Ruby classes as returned by the sqlite3 gem (verified by tests/end2end_sqlite3.rb): booleans are 0/1
        # Integers, blobs are Strings, dates are text.
        @column_mappings ||= [
          mapping('Integer', %w[int integer tinyint smallint mediumint bigint unsignedbigint int2 int8 boolean bool]),
          mapping('String', %w[blob datetime date timestamp time json jsonb uuid]),
          mapping('String', %w[character varchar varyingcharacter nchar nativecharacter nvarchar text clob],
                  prefix_based: true),
          mapping('Float', %w[real double doubleprecision float decimal numeric], prefix_based: true)
        ]
      end
    end
  end
end
