# frozen_string_literal: true

require_relative '../code'

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
      def extra_requires(_queries) = []

      # Extra gems for the generated Gemfile (e.g. `csv`, a bundled gem since Ruby 3.4).
      def extra_gems(_queries) = []

      def init_code = raise(NotImplementedError)

      def init_type = raise(NotImplementedError)

      # `def transaction` of the query class: runs the block with all queries on one connection / transaction.
      def transaction_code = raise(NotImplementedError)

      def transaction_type = "\ndef transaction: [T] () { (self) -> T } -> T"

      # RHS of the generated `<Query>Sql` constant (without the constant name).
      def query_text(query) = query.text

      def prepare_stmt(_func_name, _const) = raise(NotImplementedError)

      # array_rows: rows are read by position (needed when column names are ambiguous, e.g. sqlc.embed).
      def execute_stmt(_func_name, _has_params, array_rows: false) = raise(NotImplementedError)

      # Whether generated methods borrow the client from a ConnectionPool (`@db.with do |client|`)
      # or use the single injected connection (`client = @db`).
      def pooling_enabled? = true

      # Whether the prepared `stmt` must be closed after use (mysql2 / sqlite3 prepare on every call; unclosed
      # statements leak server resources and make SQLite refuse to COMMIT).
      def closes_statements? = false

      # How rows are read: :hash => row['col'], :array => row[0]
      def row_data_type = :hash

      # sqlc.slice is only offered by sqlc for MySQL / SQLite (`IN (/*SLICE:ids*/?)`).
      def supports_slice? = false

      def exec_rows_lines(_exec) = raise(NotImplementedError)

      def exec_last_id_lines(_exec, _query) = raise(NotImplementedError)

      def copy_from_lines(_query, _table, _columns) = raise(NotImplementedError)

      # Source of helper methods the class needs for these queries: [[code, rbs], ...]
      def helper_methods(_queries) = []

      # Ruby/RBS type of a column's DB type (no nullability / array wrapper). Enums are Strings.
      # With fallback: nil unknown types return it instead of raising (used for models, which cover every table).
      def column_type(column, fallback: :raise)
        return 'String' if catalog&.enum?(column.type)

        db_type = normalize_type(column.type.name)
        column_mappings.each do |mapping|
          matched = if mapping.prefix_based
                      mapping.db_types.any? { |d| d.start_with?(db_type) }
                    else
                      mapping.db_types.include?(db_type)
                    end
          return mapping.ruby_type if matched
        end
        return fallback unless fallback == :raise

        raise ArgumentError, "Unsupported column type: #{column.type.name}"
      end

      def query_text_constant(query)
        const = Code.upcase_first("#{query.name}Sql")
        Code.dedent_to_first_line("#{const} = %q(#{query_text(query)})")
      end

      private

      # from sqlc - char(5), int4, pg_catalog.int8, BLOB, ...
      def normalize_type(type_name) = type_name.downcase.delete_prefix('pg_catalog.')

      def driver_gems = raise(NotImplementedError)

      def column_mappings = raise(NotImplementedError)

      def mapping(ruby_type, db_types, prefix_based: false)
        ColumnMapping.new(ruby_type, db_types, prefix_based)
      end

      # 'authors' / 'extended.bios'
      def table_name(identifier)
        identifier.schema.to_s.empty? ? identifier.name : "#{identifier.schema}.#{identifier.name}"
      end
    end
  end
end
