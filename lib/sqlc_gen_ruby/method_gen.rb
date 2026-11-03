# frozen_string_literal: true

require_relative 'code'

module SqlcGenRuby
  # Builds the code (and RBS signature) of one generated query method, parameterised by the driver's
  # pooling / row-access / statement flavour. Query parameters become keyword arguments:
  #   queries.get_author(id: 1)  queries.create_author(name: 'x', bio: nil)  queries.get_authors_by_ids(ids: [1, 2])
  class MethodGen
    SLICE_HELPER = [
      "def slice_placeholders(values)\n  values.empty? ? 'SELECT NULL WHERE FALSE' : Array.new(values.size, '?').join(', ')\nend",
      'def slice_placeholders: (Array[untyped] values) -> String'
    ].freeze

    # :batch* run the query once per element of an Array of <Query>Args, on one connection
    BATCH_COMMANDS = { ':batchexec' => ':exec', ':batchone' => ':one', ':batchmany' => ':many' }.freeze
    # commands whose method takes `rows` (an Array of <Query>Args) instead of keyword arguments
    ROWS_COMMANDS = [':copyfrom', *BATCH_COMMANDS.keys].freeze

    # optional: nullable and named by the user (sqlc.arg / sqlc.narg) -> keyword argument defaulting to nil
    # reused: a later occurrence of a named parameter (MySQL sends one parameter per `?`): bound, not a keyword
    Param = Struct.new(:name, :column, :slice, :optional, :type, :reused)

    # Locals of the generated query methods; parameters with these names get a trailing underscore.
    GENERATED_LOCALS = %w[client query_params sql stmt result row].freeze

    # layout: RowLayout, types: TypeResolver, class_name: the generated query class with its module (prefixes
    # statement names, which must differ between modules that share a connection)
    def initialize(driver, layout, types, class_name)
      @driver = driver
      @layout = layout
      @types = types
      @statement_prefix = class_name.split('::').map { |part| Code.snake_case(part) }.join('_')
    end

    # `created_at > $1 AND created_at < $2` -> created_at:, created_at_2:
    def params(query)
      copy = ROWS_COMMANDS.include?(query.cmd)
      by_name = {}
      query.params.map do |p|
        column = p.column
        name = Code.param_name(column.name)
        name = copy ? @types.member_name(name) : avoid_locals(name)
        if column.is_named_param && by_name.key?(name)
          first = by_name[name]
          first.optional &&= optional?(column, query)
          next Param.new(name, column, first.slice, false, first.type, true)
        end

        name = unique_param_name(name, by_name)
        slice = column.is_sqlc_slice
        type = slice ? @types.slice_type(column, query.name) : @types.type(column, query_name: query.name)
        by_name[name] = Param.new(name, column, slice, optional?(column, query), type, false)
      end
    end

    def code(query)
      func = Code.snake_case(query.name)
      params = params(query)
      if query.cmd == ':copyfrom'
        statements = copy_statements(query, params)
        signature = '(rows)'
      elsif BATCH_COMMANDS.key?(query.cmd)
        statements = batch_statements(query, func, params)
        signature = '(rows)'
      else
        statements = query_statements(query, func, params)
        keywords = params.reject(&:reused).partition(&:optional).then do |optional, required|
          (required + optional).map { |p| p.optional ? "#{p.name}: nil" : "#{p.name}:" }
        end
        signature = keywords.empty? ? '' : "(#{keywords.join(', ')})"
      end
      doc = query.comments.map { |c| "# #{c.strip}".rstrip }.join("\n")
      method = Code.block("def #{func}#{signature}", method_body(func, statements))
      # :copyfrom / :batch* take only `rows`; the Args class gets its own exemptions
      method_params = ROWS_COMMANDS.include?(query.cmd) ? [] : params.map(&:name)
      method = Code.without_cops(method, Code.naming_cops(params: method_params))
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
      if ROWS_COMMANDS.include?(query.cmd)
        signature = "(Array[#{query.name}Args] rows)"
      else
        optional, required = params(query).reject(&:reused).partition(&:optional)
        list = (required + optional).map { |p| "#{p.optional ? '?' : ''}#{p.name}: #{p.type}" }
        signature = list.empty? ? '' : "(#{list.join(', ')})"
      end
      rbs = "def #{func}: #{signature}#{signature.empty? ? '' : ' '}-> #{return_type(query)}"
      return rbs unless query.cmd == ':one'

      "#{rbs}\n\ndef #{func}!: #{signature}#{signature.empty? ? '' : ' '}-> #{Code.upcase_first(query.name)}Row"
    end

    # [[code, rbs]] of private helper methods the generated class needs for these queries.
    def helper_methods(queries)
      helpers = @driver.helper_methods(queries)
      helpers << SLICE_HELPER if queries.any? { |q| slice?(q) }
      helpers
    end

    private

    # sqlc.narg / sqlc.arg are named parameters; behind a cast (`sqlc.narg(email)::text`) sqlc drops the flag, but
    # keeps the name without a source column.
    def optional?(column, query)
      named = column.is_named_param ||
              (!column.name.empty? && column.table.nil? && column.original_name.to_s.empty?)
      named && @types.nullable?(column, query.name)
    end

    def avoid_locals(name)
      name = "#{name}_" while GENERATED_LOCALS.include?(name)
      name
    end

    # id, id_2, id_3 for unnamed parameters of the same column (`WHERE id IN (?, ?, ?)`)
    def unique_param_name(base, taken)
      name = base
      suffix = 1
      name = "#{base}_#{suffix += 1}" while taken.key?(name)
      name
    end

    def slice?(query) = query.params.any? { |p| p.column.is_sqlc_slice }

    def return_type(query)
      case query.cmd
      when ':one' then "#{Code.upcase_first(query.name)}Row?"
      when ':many' then "Array[#{Code.upcase_first(query.name)}Row]"
      when ':execrows' then 'Integer'
      when ':execlastid' then last_id_type(query)
      when ':execresult' then 'ExecResult'
      when ':batchone' then "Array[#{query.name}Row?]"
      when ':batchmany' then "Array[Array[#{query.name}Row]]"
      else 'void'
      end
    end

    # MySQL: client.last_id (Integer); PostgreSQL / SQLite: the RETURNING column
    def last_id_type(query)
      return 'Integer' if query.columns.empty?

      type = @types.type(query.columns.first, query_name: query.name)
      type.end_with?('?') ? type : "#{type}?"
    end

    def copy_statements(query, params)
      raise ArgumentError, "#{query.name}: :copyfrom without a target table" if query.insert_into_table.nil?

      table = query.insert_into_table
      name = table.schema.to_s.empty? ? '' : "#{@driver.quote_identifier(table.schema)}."
      name += @driver.quote_identifier(table.name)
      values = params.map { |p| @driver.encode_param("row.#{p.name}", p.column) }
      verb, tail = insert_clauses(query.text)
      @driver.copy_from_lines('rows', name, params.map { |p| @driver.quote_identifier(p.column.name) }, values,
                              Code.snake_case(query.name),
                              query_name: query.name, sources: params.map(&:column), verb: verb, tail: tail)
    end

    # `INSERT OR REPLACE INTO t (a) VALUES (?) ON CONFLICT (a) DO NOTHING;` => ['INSERT OR REPLACE', 'ON CONFLICT (a) DO NOTHING']
    def insert_clauses(sql)
      sql = sql.gsub(%r{--[^\n]*|/\*.*?\*/}m, ' ')
      verb = sql[/\A\s*(.*?)\s+INTO\b/im, 1].to_s.split.join(' ').upcase
      values = sql =~ /\bVALUES\s*\(/i
      tail = values ? after_parenthesis(sql, sql.index('(', values)) : ''
      [verb, tail.strip.sub(/;\z/, '').strip]
    end

    # The text after the parenthesis opened at `start` is closed (quotes skipped).
    def after_parenthesis(sql, start)
      depth = 0
      quote = nil
      (start...sql.size).each do |i|
        char = sql[i]
        if quote
          quote = nil if char == quote
        elsif %w[' " `].include?(char)
          quote = char
        elsif char == '('
          depth += 1
        elsif char == ')' && (depth -= 1).zero?
          return sql[(i + 1)..]
        end
      end
      ''
    end

    def query_statements(query, func, params)
      if slice?(query) && !@driver.supports_slice?
        raise ArgumentError, "#{query.name}: sqlc.slice is not supported by the #{@driver.name} driver"
      end

      statements = []
      statements << query_params(params, query) unless params.empty?
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

    # Prepared once, executed for every element of rows.
    def batch_statements(query, func, params)
      raise ArgumentError, "#{query.name}: sqlc.slice cannot be used in #{query.cmd}" if slice?(query)

      const = Code.sql_constant(query.name)
      stmt_name = "#{@statement_prefix}_#{func}"
      prepare = @driver.prepare_stmt(stmt_name, const)
      cmd = BATCH_COMMANDS.fetch(query.cmd)
      body = []
      body << @driver.query_params(query, params, value_prefix: 'args.') unless params.empty?
      commands = command_statements(query, stmt_name, const, !params.empty?, cmd: cmd)
      commands.pop if cmd == ':exec' # the trailing nil
      if @driver.prepares_batch_rows?
        body << prepare
        body << Code.block('begin', commands.join("\n")).sub(/\nend\z/, "\nensure\n  stmt.close\nend")
      else
        body.concat(commands)
      end
      block_arg = params.empty? ? '_args' : 'args'
      loop = Code.block("rows.#{cmd == ':exec' ? 'each' : 'map'} do |#{block_arg}|", body.join("\n"))
      commands = cmd == ':exec' ? [loop, 'nil'] : [loop]
      return commands if @driver.prepares_batch_rows?

      statements = [prepare].compact
      if @driver.closes_statements?
        statements << Code.block('begin', commands.join("\n")).sub(/\nend\z/, "\nensure\n  stmt.close\nend")
      else
        statements.concat(commands)
      end
      statements
    end

    def query_params(params, query)
      @driver.query_params(query, params)
    end

    # sql = FOO_SQL.gsub('/*SLICE:ids*/?', slice_placeholders(ids)) - once per slice
    def slice_sql(const, params)
      params.select { |p| p.slice && !p.reused }.each_with_index.map do |p, i|
        "sql = #{i.zero? ? const : 'sql'}.gsub('/*SLICE:#{p.column.name}*/?', slice_placeholders(#{p.name}))"
      end.join("\n")
    end

    # The value of the last expression is the return value of the method (no explicit `return`).
    def command_statements(query, stmt_name, const, has_params, cmd: query.cmd)
      exec = @driver.execute_stmt(stmt_name, const, has_params, array_rows: !query.columns.empty? && @layout.array_rows?(query))
      case cmd
      when ':one'
        ["result = #{exec}", 'row = result.first', "row && #{new_row(query)}"]
      when ':many'
        ["result = #{exec}", Code.block('result.map do |row|', new_row(query))]
      when ':exec' then @driver.exec_lines(exec, query)
      when ':execrows' then @driver.exec_rows_lines(exec, query)
      when ':execlastid' then @driver.exec_last_id_lines(exec, query)
      when ':execresult' then exec_result_lines(exec)
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
        value = if entry.table
                  values = entry.table.columns.each_index.map { |i| "row[#{index + i}]" }
                  index += values.size
                  names = entry.table.columns.map { |c| @types.member_name(c.name) }
                  model = "#{entry.table.model_name}.new(#{constructor_args(names, values).join(', ')})"
                  entry.optional ? "#{missing_row_check(entry.table, values)} ? nil : #{model}" : model
                else
                  index += 1
                  array ? "row[#{index - 1}]" : "row[#{Code.string_literal(entry.column.name)}]"
                end
        [entry.attr, value]
      end
      args = constructor_args(args.map(&:first), args.map(&:last))
      row_class = "#{Code.upcase_first(query.name)}Row"
      wrap = "#{row_class}.new(#{args.join(', ')})".length > 100
      "#{row_class}.new(#{Code.comma_join(args, wrap: wrap)})"
    end

    # Struct rows (Ruby < 3.2) are built with keywords (keyword_init: true), Data rows positionally.
    def exec_result_lines(exec)
      *lines, rows_affected, last_insert_id = @driver.exec_result_lines(exec)
      lines << "ExecResult.new(#{constructor_args(%w[rows_affected last_insert_id], [rows_affected, last_insert_id]).join(', ')})"
    end

    def constructor_args(names, values)
      @types.keyword_rows? ? names.zip(values).map { |n, v| "#{n}: #{v}" } : values
    end

    # The outer side of a join is missing when its NOT NULL columns (all columns if it has none) are NULL.
    def missing_row_check(table, values)
      required = table.columns.each_index.select { |i| table.columns[i].not_null }
      required = table.columns.each_index.to_a if required.empty?
      required.map { |i| "#{values[i]}.nil?" }.join(' && ')
    end
  end
end
