# frozen_string_literal: true

require_relative 'code'

module SqlcGenRuby
  # Port of Drivers/MethodGen.cs: builds the code (and RBS signature) of one generated query method,
  # parameterised by the driver's pooling / row-access / statement flavour.
  class MethodGen
    SLICE_HELPER = [
      "def slice_placeholders(values)\n\tvalues.empty? ? 'NULL' : Array.new(values.size, '?').join(', ')\nend",
      'def slice_placeholders: (Array[untyped]) -> String'
    ].freeze

    # layout: Generator#row_layout; types: TypeResolver
    def initialize(driver, layout, types)
      @driver = driver
      @layout = layout
      @types = types
    end

    def code(query)
      func = Code.snake_case(query.name)
      args_var = Code.snake_case("#{query.name}Args")
      statements = query.cmd == ':copyfrom' ? copy_statements(query) : query_statements(query, func, args_var)
      params = query.params.empty? ? '' : "(#{args_var})"
      Code.block("def #{func}#{params}", method_body(statements, query.cmd))
    end

    def type(query)
      func = Code.snake_case(query.name)
      params = if query.cmd == ':copyfrom' then "(Array[#{query.name}Args]) "
               elsif query.params.empty? then ''
               else "(#{query.name}Args) "
               end
      "\ndef #{func}: #{params}-> #{return_type(query)}"
    end

    # [[code, rbs]] of private helper methods the generated class needs for these queries.
    def helper_methods(queries)
      helpers = @driver.helper_methods(queries)
      helpers << SLICE_HELPER if queries.any? { |q| slice?(q) }
      helpers
    end

    private

    def slice?(query) = query.params.any? { |p| p.column.is_sqlc_slice }

    def return_type(query)
      case query.cmd
      when ':one' then "#{query.name}Row?"
      when ':many' then "Array[#{query.name}Row]"
      when ':execrows' then 'Integer'
      when ':execlastid' then last_id_type(query)
      else 'void'
      end
    end

    # MySQL: client.last_id (Integer); PostgreSQL / SQLite: the RETURNING column
    def last_id_type(query)
      return 'Integer' if query.columns.empty?

      @types.type(query.columns.first, query_name: query.name)
    end

    def copy_statements(query)
      raise ArgumentError, "#{query.name}: :copyfrom without a target table" if query.insert_into_table.nil?

      table = query.insert_into_table
      name = table.schema.to_s.empty? ? table.name : "#{table.schema}.#{table.name}"
      @driver.copy_from_lines(query, name, query.params.map { |p| p.column.name })
    end

    def query_statements(query, func, args_var)
      has_params = !query.params.empty?
      if slice?(query) && !@driver.supports_slice?
        raise ArgumentError, "#{query.name}: sqlc.slice is not supported by the #{@driver.name} driver"
      end

      statements = []
      statements << query_params(args_var, query.params) if has_params
      sql_const = "#{query.name}Sql"
      if slice?(query)
        statements << slice_sql(sql_const, args_var, query.params)
        sql_const = 'sql'
      end
      statements << @driver.prepare_stmt(func, sql_const)
      commands = command_statements(query, func, has_params)
      if @driver.closes_statements?
        statements << Code.block('begin', commands.join("\n")).sub(/\nend\z/, "\nensure\n\tstmt.close\nend")
      else
        statements.concat(commands)
      end
      statements
    end

    def query_params(args_var, params)
      list = params.map do |p|
        access = "#{args_var}.#{p.column.name}"
        p.column.is_sqlc_slice ? "*#{access}" : access
      end
      "query_params = [#{Code.comma_join(list)}]"
    end

    # sql = FooSql.sub('/*SLICE:ids*/?', slice_placeholders(args.ids)).sub(...)
    def slice_sql(sql_const, args_var, params)
      subs = params.select { |p| p.column.is_sqlc_slice }.map do |p|
        ".sub('/*SLICE:#{p.column.name}*/?', slice_placeholders(#{args_var}.#{p.column.name}))"
      end
      "sql = #{sql_const}#{subs.join}"
    end

    def command_statements(query, func, has_params)
      array_rows = @layout.array_rows?(query)
      exec = @driver.execute_stmt(func, has_params, array_rows: array_rows)
      case query.cmd
      when ':one'
        ["result = #{exec}",
         'row = result.first',
         'return nil if row.nil?',
         "entity = #{new_row(query)}",
         'return entity']
      when ':many'
        ["result = #{exec}",
         'entities = []',
         Code.block('result.each do |row|', "entities << #{new_row(query)}"),
         'return entities']
      when ':exec' then [exec]
      when ':execrows' then @driver.exec_rows_lines(exec)
      when ':execlastid' then @driver.exec_last_id_lines(exec, query)
      else raise ArgumentError, "unsupported query command: #{query.cmd}"
      end
    end

    # :execlastid / :copyfrom use the pool even where :one/:many/:exec would not (they were pooled in the C#
    # implementation too).
    def method_body(statements, _cmd)
      body = statements.join("\n")
      return Code.block('@db.with do |client|', body) if @driver.pooling_enabled?

      "client = @db\n#{body}"
    end

    def new_row(query)
      array = @layout.array_rows?(query)
      index = 0
      args = @layout.entries(query).map do |entry|
        if entry.table
          values = entry.table.columns.each_index.map { |i| "row[#{index + i}]" }
          index += values.size
          "#{entry.table.model_name}.new(#{Code.comma_join(values)})"
        else
          access = array ? "row[#{index}]" : "row['#{entry.column.name}']"
          index += 1
          access
        end
      end
      "#{query.name}Row.new(#{Code.comma_join(args)})"
    end
  end
end
