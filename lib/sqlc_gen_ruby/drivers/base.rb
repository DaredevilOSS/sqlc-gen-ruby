# frozen_string_literal: true

require_relative '../code'

module SqlcGenRuby
  module Drivers
    # Port of Drivers/DbDriver.cs (+ ColumnMappingConfig.cs, RowDataType.cs, Variable.cs).
    #
    # A driver supplies the DB-specific snippets; Generator/MethodGen assemble the file around them.
    # Every `*_code` / `*_type` pair mirrors BuildCode / BuildType of the C# syntax-tree nodes.
    class Base
      ColumnMapping = Struct.new(:ruby_type, :db_types, :prefix_based)

      # Names of the generated variables (Variable.cs): snake_case(AsVar) / '@' + snake_case(AsProperty).
      DB = '@db'
      CLIENT = 'client'
      STMT = 'stmt'
      RESULT = 'result'
      ROW = 'row'
      ENTITY = 'entity'
      ENTITIES = 'entities'
      QUERY_PARAMS = 'query_params'

      # Name used for the generated module (`<Name>Codegen`) - same as the C# DriverName enum value.
      def name = raise(NotImplementedError)

      def required_gems = ['connection_pool', *driver_gems]

      def init_code = raise(NotImplementedError)

      def init_type = raise(NotImplementedError)

      # RHS of the generated `<Query>Sql` constant (without the constant name).
      def query_text(query) = query.text

      def prepare_stmt(_func_name, _const) = raise(NotImplementedError)

      def execute_stmt(_func_name, _has_params) = raise(NotImplementedError)

      # Whether generated methods borrow the client from a ConnectionPool (`@db.with do |client|`)
      # or use the single injected connection (`client = @db`).
      def pooling_enabled? = true

      # How rows are read: :hash => row['col'], :array => row[0]
      def row_data_type = :hash

      def supports_exec_last_id? = false

      def column_type(column)
        db_type = column.type.name.downcase # from sqlc - char(5), int4, float8, blob, ...
        column_mappings.each do |mapping|
          matched = if mapping.prefix_based
                      mapping.db_types.any? { |d| d.start_with?(db_type) }
                    else
                      mapping.db_types.include?(db_type)
                    end
          return mapping.ruby_type if matched
        end
        raise ArgumentError, "Unsupported column type: #{column.type.name}"
      end

      def query_text_constant(query)
        const = Code.upcase_first("#{query.name}Sql")
        Code.dedent_to_first_line("#{const} = %q(#{query_text(query)})")
      end

      private

      def driver_gems = raise(NotImplementedError)

      def column_mappings = raise(NotImplementedError)

      def mapping(ruby_type, db_types, prefix_based: false)
        ColumnMapping.new(ruby_type, db_types, prefix_based)
      end
    end
  end
end
