# frozen_string_literal: true

require_relative '../code'
require_relative '../ruby_version'

module SqlcGenRuby
  module Drivers
    # Port of Drivers/DbDriver.cs (+ ColumnMappingConfig.cs, RowDataType.cs, Variable.cs), extended with the hooks
    # for :execrows / :execlastid / :copyfrom / sqlc.slice / transactions.
    #
    # A driver supplies the DB-specific snippets; Generator/MethodGen assemble the file around them.
    # Methods returning "lines" return an Array of Ruby source lines for the body of the generated method (inside
    # the connection block).
    class Base
      ColumnMapping = Struct.new(:ruby_type, :db_types, :prefix_based)

      # Set by the Generator: gives access to enums (a column of an enum type is a String).
      attr_accessor :catalog

      # Name used for the generated module (`<Name>Codegen`) - same as the C# DriverName enum value.
      def name = raise(NotImplementedError)

      def required_gems = ['connection_pool', *driver_gems]

      # Extra `require`s needed by generated code for these queries (stdlib or gems), beyond required_gems.
      def extra_requires(_queries, _ruby_version) = []

      # Extra gems for the generated Gemfile (e.g. `csv`, a bundled gem since Ruby 3.4).
      def extra_gems(_queries) = []

      # Ruby source (and its RBS) placed in the module next to the query classes: shared helpers / constants.
      # [[code, rbs], ...]
      def module_members = []

      # Public methods of the generated query class that are not queries: constructor, `connect`, `transaction`.
      # [[code, rbs], ...]
      def class_methods(_ruby_version = nil) = raise(NotImplementedError)

      # Private helpers of the query class. [[code, rbs], ...]
      def private_methods(_ruby_version = nil) = []

      # How a query method acquires the database connection (yielding `client`).
      def client_block(func) = "with_client('#{func}') do |client|"

      # RHS of the generated `<Query>Sql` constant (without the constant name).
      def query_text(query) = query.text

      # Ruby expressions for the parameters passed to one generated query method.
      def query_params(_query, params)
        list = params.map { |p| p.slice ? "*#{p.name}" : encode_param(p.name, p.column) }
        "query_params = [#{Code.comma_join(list)}]"
      end

      # stmt_name: unique per query (e.g. query_sql_get_author), only meaningful for named server-side statements.
      def prepare_stmt(_stmt_name, _const) = raise(NotImplementedError)

      # array_rows: rows are read by position (needed when column names are ambiguous, e.g. sqlc.embed).
      def execute_stmt(_stmt_name, _const, _has_params, array_rows: false) = raise(NotImplementedError)

      # Whether the prepared `stmt` must be closed after use (mysql2 / sqlite3 prepare on every call; unclosed
      # statements leak server resources and make SQLite refuse to COMMIT).
      def closes_statements? = false

      # How rows are read: :hash => row['col'], :array => row[0]
      def row_data_type = :hash

      # sqlc.slice is only offered by sqlc for MySQL / SQLite (`IN (/*SLICE:ids*/?)`).
      def supports_slice? = false

      def exec_lines(exec, _query) = [exec, 'nil']

      def exec_rows_lines(_exec, _query) = raise(NotImplementedError)

      def exec_last_id_lines(_exec, _query) = raise(NotImplementedError)

      # table: quoted SQL name; columns: quoted SQL column names; values: Ruby expressions of the row values;
      # sources: the sqlc columns of the values; verb: the SQL before INTO (`INSERT OR IGNORE`); tail: the SQL after
      # the VALUES tuple (`ON CONFLICT ...`)
      def copy_from_lines(_rows_var, _table, _columns, _values, _label, query_name:, sources:, verb:, tail:)
        raise(NotImplementedError)
      end

      # :batch* prepare the statement for every row instead of once (mysql2 corrupts reused statements' parameters).
      def prepares_batch_rows? = false

      # SQL identifier quoting for the statements the plugin writes itself (:copyfrom).
      def quote_identifier(name) = %("#{name.gsub('"', '""')}")

      # Ruby expression that turns a parameter value into what the driver can bind (e.g. bytea escaping).
      def encode_param(expr, _column) = expr

      # :execresult -> [*statements, rows_affected expression, last_insert_id expression]
      def exec_result_lines(_exec) = raise(NotImplementedError)

      # Private helper methods the class needs for these queries: [[code, rbs], ...]
      def helper_methods(_queries) = []

      # Ruby/RBS type of a column's DB type (no nullability / array wrapper). Enums are Strings.
      # With fallback: nil unknown types return it instead of raising (used for models, which cover every table).
      def column_type(column, fallback: :raise)
        return 'String' if catalog&.enum?(column.type) || catalog&.composite?(column.type)

        db_type = normalize_type(column.type.name)
        return 'untyped' if db_type == 'any' # sqlc could not infer the type of the expression

        column_mappings.each do |mapping|
          matched = if mapping.prefix_based
                      mapping.db_types.any? { |d| db_type.start_with?(d) }
                    else
                      mapping.db_types.include?(db_type)
                    end
          return mapping.ruby_type if matched
        end
        affinity = affinity_type(db_type)
        return affinity if affinity
        return fallback unless fallback == :raise

        raise ArgumentError, "Unsupported column type: #{column.type.name}"
      end

      # The SQL as a frozen raw heredoc (no escaping issues, readable, no paren-balancing problems).
      def query_text_constant(query)
        const = Code.sql_constant(query.name)
        text = query_text(query)
        terminator = 'SQL'
        terminator += '_' while text.lines.any? { |line| line.strip == terminator }
        "#{const} = <<~'#{terminator}'\n#{Code.indent(text)}\n#{terminator}"
      end

      ISOLATION_LEVELS = <<~'RUBY'.chomp
        ISOLATION_LEVELS = {
          read_uncommitted: 'READ UNCOMMITTED',
          read_committed: 'READ COMMITTED',
          repeatable_read: 'REPEATABLE READ',
          serializable: 'SERIALIZABLE'
        }.freeze
      RUBY

      # Logs "QuerySql#get_author (0.4ms)" at debug level when the object was created with `logger:`.
      INSTRUMENT = <<~'RUBY'.chomp
        def instrument(name)
          return yield unless @logger

          started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          begin
            yield
          ensure
            elapsed = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000
            @logger.debug { format('%<class>s#%<name>s (%<ms>.1fms)', class: self.class.name, name: name, ms: elapsed) }
          end
        end
      RUBY

      INSTRUMENT_RBS = 'def instrument: [T] (String name) { () -> T } -> T'

      NOT_FOUND = <<~'RUBY'.chomp
        # Raised by the bang variants (get_author!) when the query returns no row.
        class NotFound < StandardError; end
      RUBY

      ISOLATION_RBS = 'ISOLATION_LEVELS: Hash[Symbol, String]'

      TRANSACTION_RBS = 'def transaction: [T] (?isolation: (:read_uncommitted | :read_committed | :repeatable_read | ' \
                        ':serializable)?) { (self) -> T } -> T'

      private

      def legacy_transaction_template(template, ruby_version, old_condition, guarded_condition)
        return template unless ruby_version < RubyVersion.new(3, 3)

        template = template.sub(/^( +)def transaction\b/) do
          indent = Regexp.last_match(1)
          "#{indent}# On Ruby <3.3 with timeout <0.4, break / return / throw roll back because Timeout cannot be told apart.\n" \
            "#{indent}# Add gem 'timeout', '>= 0.4' to keep these exits committing.\n#{indent}def transaction"
        end
        template = template.sub(/^( +)failed = false\n\1begin\n( +)yield self\n/) do
          indent = Regexp.last_match(1)
          yield_indent = Regexp.last_match(2)
          "#{indent}failed = false\n#{indent}completed = false\n#{indent}begin\n" \
            "#{yield_indent}result = yield self\n#{yield_indent}completed = true\n#{yield_indent}result\n"
        end
        template.sub(old_condition, guarded_condition)
      end

      def timeout_exit_methods(ruby_version)
        return [] unless ruby_version < RubyVersion.new(3, 3)

        [[TIMEOUT_EXIT_HELPER, TIMEOUT_EXIT_HELPER_RBS]]
      end

      # from sqlc - char(5), int4, pg_catalog.int8, BLOB, VARCHAR(255), ... => char, int4, int8, blob, varchar
      def normalize_type(type_name) = type_name.downcase.delete_prefix('pg_catalog.').sub(/\s*\(.*\)\z/, '')

      # Type of a declared type no mapping matched (SQLite's type affinity), nil for none.
      def affinity_type(_db_type) = nil

      def driver_gems = raise(NotImplementedError)

      def column_mappings = raise(NotImplementedError)

      def mapping(ruby_type, db_types, prefix_based: false)
        ColumnMapping.new(ruby_type, db_types, prefix_based)
      end

      # 'authors' / 'extended.bios'
      def table_name(identifier)
        identifier.schema.to_s.empty? ? identifier.name : "#{identifier.schema}.#{identifier.name}"
      end

      TIMEOUT_EXIT_HELPER = <<~'RUBY'.chomp
        def timeout_exits_with_throw?
          !!(defined?(::Timeout::VERSION) &&
             (::Timeout::VERSION.split('.').map(&:to_i) <=> [0, 4]).negative?)
        end
      RUBY
      TIMEOUT_EXIT_HELPER_RBS = 'def timeout_exits_with_throw?: () -> bool'
    end
  end
end
