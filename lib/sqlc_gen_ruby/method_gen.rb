# frozen_string_literal: true

require_relative 'code'

module SqlcGenRuby
  # Port of Drivers/MethodGen.cs: builds the code (and RBS signature) of one generated query method,
  # parameterised by the driver's pooling / row-access / statement flavour.
  class MethodGen
    def initialize(driver)
      @driver = driver
    end

    def code(query)
      func = Code.snake_case(query.name)
      args_var = Code.snake_case("#{query.name}Args")
      has_params = !query.params.empty?

      statements = []
      statements << query_params(args_var, query.params) if has_params
      statements << @driver.prepare_stmt(func, "#{query.name}Sql")
      statements.concat(command_statements(query, func, has_params))

      params = has_params ? "(#{args_var})" : ''
      Code.block("def #{func}#{params}", method_body(statements, query.cmd))
    end

    def type(query)
      func = Code.snake_case(query.name)
      params = query.params.empty? ? '' : "(#{query.name}Args) "
      "\ndef #{func}: #{params}-> #{return_type(query)}"
    end

    private

    def return_type(query)
      case query.cmd
      when ':one' then "#{query.name}Row?"
      when ':execlastid' then 'Integer'
      else 'void'
      end
    end

    def query_params(args_var, params)
      list = Code.comma_join(params.map { |p| "#{args_var}.#{p.column.name}" })
      "query_params = [#{list}]"
    end

    def command_statements(query, func, has_params)
      exec = @driver.execute_stmt(func, has_params)
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
      when ':exec'
        [exec]
      when ':execlastid'
        unless @driver.supports_exec_last_id?
          raise ArgumentError, "the #{query.cmd} command is not supported by the #{@driver.name} driver"
        end

        [exec, 'return client.last_id']
      else
        raise ArgumentError, "unsupported query command: #{query.cmd}"
      end
    end

    # :execlastid is always pooled (the C# ExecLastIdDeclare had no non-pooled variant).
    def method_body(statements, cmd)
      body = statements.join("\n")
      return Code.block('@db.with do |client|', body) if @driver.pooling_enabled? || cmd == ':execlastid'

      "client = @db\n#{body}"
    end

    def new_row(query)
      args = Code.comma_join(query.columns.each_with_index.map { |c, i| row_access(c, i) })
      "#{query.name}Row.new(#{args})"
    end

    def row_access(column, index)
      @driver.row_data_type == :hash ? "row['#{column.name}']" : "row[#{index}]"
    end
  end
end
