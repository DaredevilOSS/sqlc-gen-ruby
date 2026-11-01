# frozen_string_literal: true

require_relative 'code'

module SqlcGenRuby
  # Builds the code (and RBS signature) of one generated query method, parameterised by the driver's
  # pooling / row-access / statement flavour. Query parameters become keyword arguments:
  #   queries.get_author(id: 1)  queries.create_author(name: 'x', bio: nil)  queries.get_authors_by_ids(ids: [1, 2])
  class MethodGen
    SLICE_HELPER = [
      "def slice_placeholders(values)\n  values.empty? ? 'NULL' : Array.new(values.size, '?').join(', ')\nend",
      'def slice_placeholders: (Array[untyped] values) -> String'
    ].freeze

    # optional: nullable and named by the user (sqlc.arg / sqlc.narg) -> keyword argument defaulting to nil
    Param = Struct.new(:name, :column, :slice, :optional, :type)

    # layout: RowLayout, types: TypeResolver, class_name: the generated query class (prefixes statement names)
    def initialize(driver, layout, types, class_name)
      @driver = driver
      @layout = layout
      @types = types
      @statement_prefix = Code.snake_case(class_name)
    end

    # `created_at > $1 AND created_at < $2` -> created_at:, created_at_2:
    def params(query)
      names = unique_param_names(query.params.map { |p| Code.param_name(p.column.name) })
      query.params.zip(names).map do |p, name|
        column = p.column
        slice = column.is_sqlc_slice
        type = slice ? @types.slice_type(column, query.name) : @types.type(column, query_name: query.name)
        Param.new(name, column, slice, column.is_named_param && @types.nullable?(column, query.name), type)
      end
    end

    def code(query)
      func = Code.snake_case(query.name)
      params = params(query)
      if query.cmd == ':copyfrom'
        statements = copy_statements(query, params)
        signature = '(rows)'
      else
        statements = query_statements(query, func, params)
        signature = params.empty? ? '' : "(#{params.map { |p| p.optional ? "#{p.name}: nil" : "#{p.name}:" }.join(', ')})"
      end
      doc = query.comments.map { |c| "# #{c.strip}".rstrip }.join("\n")
      method = Code.block("def #{func}#{signature}", method_body(func, statements))
      method = "#{doc}\n#{method}" unless doc.empty?
      query.cmd == ':one' ? "#{method}\n\n#{bang_method(query, func)}" : method
    end

    # get_author! raises NotFound instead of returning nil (like find_by vs find!)
    def bang_method(query, func)
      Code.block("# Like ##{func}, but raises NotFound when there is no row.\ndef #{func}!(...)",
                 "#{func}(...) || raise(NotFound, '#{query.name} returned no row')")
    end

    def type(query)
      func = Code.snake_case(query.name)
      if query.cmd == ':copyfrom'
        signature = "(Array[#{query.name}Args] rows)"
      else
        list = params(query).map { |p| "#{p.optional ? '?' : ''}#{p.name}: #{p.type}" }
        signature = list.empty? ? '' : "(#{list.join(', ')})"
      end
      rbs = "def #{func}: #{signature}#{signature.empty? ? '' : ' '}-> #{return_type(query)}"
      return rbs unless query.cmd == ':one'

      "#{rbs}\n\ndef #{func}!: #{signature}#{signature.empty? ? '' : ' '}-> #{query.name}Row"
    end

    # [[code, rbs]] of private helper methods the generated class needs for these queries.
    def helper_methods(queries)
      helpers = @driver.helper_methods(queries)
      helpers << SLICE_HELPER if queries.any? { |q| slice?(q) }
      helpers
    end

    private

    def unique_param_names(bases)
      used = []
      bases.map do |base|
        name = base
        suffix = 1
        name = "#{base}_#{suffix += 1}" while used.include?(name) || (name != base && bases.include?(name))
        used << name
        name
      end
    end

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

    def copy_statements(query, params)
      raise ArgumentError, "#{query.name}: :copyfrom without a target table" if query.insert_into_table.nil?

      table = query.insert_into_table
      name = table.schema.to_s.empty? ? table.name : "#{table.schema}.#{table.name}"
      @driver.copy_from_lines('rows', name, params.map { |p| p.column.name }, params.map { |p| Code.attr_name(p.name) },
                              Code.snake_case(query.name))
    end

    def query_statements(query, func, params)
      if slice?(query) && !@driver.supports_slice?
        raise ArgumentError, "#{query.name}: sqlc.slice is not supported by the #{@driver.name} driver"
      end

      statements = []
      statements << query_params(params) unless params.empty?
      const = Code.sql_constant(query.name)
      if slice?(query)
        statements << slice_sql(const, params)
        const = 'sql'
      end
      stmt_name = "#{@statement_prefix}_#{func}"
      prepare = @driver.prepare_stmt(stmt_name, const)
      statements << prepare if prepare
      commands = command_statements(query, stmt_name, const, !params.empty?)
      if @driver.closes_statements?
        statements << Code.block('begin', commands.join("\n")).sub(/\nend\z/, "\nensure\n  stmt.close\nend")
      else
        statements.concat(commands)
      end
      statements
    end

    def query_params(params)
      list = params.map { |p| p.slice ? "*#{p.name}" : p.name }
      "query_params = [#{Code.comma_join(list)}]"
    end

    # sql = FOO_SQL.sub('/*SLICE:ids*/?', slice_placeholders(ids)) - once per slice
    def slice_sql(const, params)
      params.select(&:slice).each_with_index.map do |p, i|
        "sql = #{i.zero? ? const : 'sql'}.sub('/*SLICE:#{p.column.name}*/?', slice_placeholders(#{p.name}))"
      end.join("\n")
    end

    # The value of the last expression is the return value of the method (no explicit `return`).
    def command_statements(query, stmt_name, const, has_params)
      exec = @driver.execute_stmt(stmt_name, const, has_params, array_rows: @layout.array_rows?(query))
      case query.cmd
      when ':one'
        ["result = #{exec}", 'row = result.first', "row && #{new_row(query)}"]
      when ':many'
        ["result = #{exec}", Code.block('result.map do |row|', new_row(query))]
      when ':exec' then [exec, 'nil']
      when ':execrows' then @driver.exec_rows_lines(exec)
      when ':execlastid' then @driver.exec_last_id_lines(exec, query)
      else raise ArgumentError, "unsupported query command: #{query.cmd}"
      end
    end

    def method_body(func, statements)
      Code.block(@driver.client_block(func), statements.join("\n"))
    end

    def new_row(query)
      array = @layout.array_rows?(query)
      index = 0
      args = @layout.entries(query).map do |entry|
        if entry.table
          values = entry.table.columns.each_index.map { |i| "row[#{index + i}]" }
          index += values.size
          model = "#{entry.table.model_name}.new(#{Code.comma_join(values)})"
          entry.optional ? "#{missing_row_check(entry.table, values)} ? nil : #{model}" : model
        else
          access = array ? "row[#{index}]" : "row['#{entry.column.name}']"
          index += 1
          access
        end
      end
      "#{query.name}Row.new(#{Code.comma_join(args)})"
    end

    # The outer side of a join is missing when its NOT NULL columns (all columns if it has none) are NULL.
    def missing_row_check(table, values)
      required = table.columns.each_index.select { |i| table.columns[i].not_null }
      required = table.columns.each_index.to_a if required.empty?
      required.map { |i| "#{values[i]}.nil?" }.join(' && ')
    end
  end
end
