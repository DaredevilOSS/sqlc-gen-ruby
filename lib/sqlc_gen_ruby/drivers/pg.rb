# frozen_string_literal: true

require_relative 'base'

module SqlcGenRuby
  module Drivers
    # PostgreSQL via the `pg` gem. Prepared statements are named per query class and prepared once per connection.
    class Pg < Base
      def initialize(prepared_statements: true)
        super()
        @prepared = prepared_statements
      end

      def name = 'Pg'

      def module_members
        [
          [CONNECTION_STATE, CONNECTION_STATE_RBS],
          [ISOLATION_LEVELS, ISOLATION_RBS]
        ]
      end

      def class_methods
        [
          [NOT_FOUND, "class NotFound < StandardError\nend"],
          [CONNECT, 'def self.connect: (Hash[untyped, untyped] pg_params, ?logger: untyped, **untyped pool_options) -> instance'],
          [INITIALIZE, 'def initialize: (untyped db, ?logger: untyped) -> void'],
          [TRANSACTION, TRANSACTION_RBS]
        ]
      end

      def private_methods
        [
          [INSTRUMENT, INSTRUMENT_RBS],
          [WITH_CLIENT, 'def with_client: [T] (String name) { (untyped) -> T } -> T'],
          [CONFIGURE, "def configure: (untyped client) -> void\n\ndef string_arrays: (untyped client) -> untyped"]
        ]
      end

      # Set is only autoloaded since Ruby 3.2
      def extra_requires(_queries, ruby_version) = ruby_version.immutable_data_supported? ? [] : %w[set]

      def prepare_stmt(stmt_name, const)
        return nil unless @prepared

        body = "client.prepare('#{stmt_name}', #{const})\nclient.prepared_statements.add('#{stmt_name}')"
        Code.block("unless client.prepared_statements.include?('#{stmt_name}')", body)
      end

      # With preparedStatements: false (e.g. behind pgbouncer in transaction mode) the SQL is sent with every call.
      def execute_stmt(stmt_name, const, has_params, array_rows: false)
        args = has_params ? ', query_params' : ''
        call = if @prepared
                 "client.exec_prepared('#{stmt_name}'#{args})"
               else
                 "client.exec_params(#{const}#{has_params ? ', query_params' : ', []'})"
               end
        array_rows ? "#{call}.values" : call
      end

      def exec_rows_lines(exec, _query) = ["result = #{exec}", 'result.cmd_tuples']

      # PostgreSQL has no last insert id (use RETURNING).
      def exec_result_lines(exec) = ["result = #{exec}", 'result.cmd_tuples', 'nil']

      # Relies on a user-written `RETURNING <id>`; nil when no row is returned (e.g. ON CONFLICT DO NOTHING).
      def exec_last_id_lines(exec, query)
        if query.columns.empty?
          raise ArgumentError, "#{query.name}: :execlastid on PostgreSQL needs a RETURNING clause"
        end

        ["result = #{exec}", 'row = result.first', "row && row['#{query.columns.first.name}']"]
      end

      # COPY ... FROM STDIN, one row at a time through the pg gem's CopyRow encoder.
      def copy_from_lines(rows_var, table, columns, values, _label, query_name:, sources:, verb:, tail:)
        unless verb == 'INSERT' && tail.empty?
          raise ArgumentError, "#{query_name}: :copyfrom on PostgreSQL (COPY) takes a plain INSERT ... VALUES (...), " \
                               'without ON CONFLICT / RETURNING'
        end

        put = Code.block("#{rows_var}.each do |row|", "client.put_copy_data([#{values.join(', ')}])")
        [
          'encoder = PG::TextEncoder::CopyRow.new(type_map: client.type_map_for_queries)',
          Code.block("client.copy_data('COPY #{table} (#{columns.join(', ')}) FROM STDIN', encoder) do", put),
          'nil'
        ]
      end

      # bytea, json / jsonb (BasicTypeMapForQueries sends a Ruby Array as a PG array), float (the pg gem's encoder
      # drops digits) and arrays (the pg gem types an Array from its first element)
      def encode_param(expr, column)
        helper, kind = encoder_for(column)
        return expr unless helper

        kind ? "#{helper}(#{expr}, :#{kind})" : "#{helper}(#{expr})"
      end

      def helper_methods(queries)
        used = queries.flat_map { |q| q.params.map { |p| encoder_for(p.column)&.first } }.compact.uniq
        ENCODERS.select { |name, _| used.include?(name) }.values
      end

      ENCODERS = {
        'encode_bytea' => [<<~'RUBY'.chomp, 'def encode_bytea: (String? value) -> String?'],
          # bytea parameters are sent escaped: binary Strings (NUL bytes, invalid UTF-8) are not valid text.
          def encode_bytea(value)
            value && PG::TextEncoder::Bytea.new.encode(value)
          end
        RUBY
        'encode_json' => [<<~'RUBY'.chomp, 'def encode_json: (untyped value) -> untyped'],
          # json / jsonb parameters: an Array is a JSON array, not a PG array (Hashes and JSON text pass through).
          def encode_json(value)
            value.is_a?(Array) ? PG::TextEncoder::JSON.new.encode(value) : value
          end
        RUBY
        'encode_float' => [<<~'RUBY'.chomp, 'def encode_float: (untyped value) -> untyped'],
          # Float#to_s is the shortest text that reads back as the same Float (the pg gem's encoder drops digits).
          def encode_float(value)
            value.is_a?(Float) ? value.to_s : value
          end
        RUBY
        'encode_array' => [<<~'RUBY'.chomp, <<~'RBS'.chomp]
          # Array parameters are sent as array literals, which the server converts to the parameter's type (the pg gem
          # would type them from their first element: wrong for [], [nil, ...], bytea[], json[]).
          def encode_array(value, kind = :value)
            return value unless value.is_a?(Array)

            PG::TextEncoder::Array.new(elements_type: PG::TextEncoder::String.new).encode(array_elements(value, kind))
          end

          def array_elements(values, kind)
            values.map do |value|
              case value
              when nil then nil
              when Array then kind == :json ? PG::TextEncoder::JSON.new.encode(value) : array_elements(value, kind)
              when Hash then PG::TextEncoder::JSON.new.encode(value)
              when String then kind == :bytea ? PG::TextEncoder::Bytea.new.encode(value) : value
              when Time then PG::TextEncoder::TimestampWithTimeZone.new.encode(value)
              else defined?(IPAddr) && value.is_a?(IPAddr) ? "#{value}/#{value.prefix}" : value.to_s
              end
            end
          end
        RUBY
          def encode_array: (Array[untyped]? value, ?Symbol kind) -> untyped

          def array_elements: (Array[untyped] values, Symbol kind) -> Array[untyped]
        RBS
      }.freeze

      CONNECTION_STATE = <<~'RUBY'.chomp
        # State kept on every PG::Connection the first time it is used.
        module ConnectionState
          # Names of the statements prepared on this connection; forgotten when the server session changes
          # (PG::Connection#reset after a failover / terminated backend).
          def prepared_statements
            if @prepared_statements_pid != backend_pid
              @prepared_statements = Set[]
              @prepared_statements_pid = backend_pid
            end
            @prepared_statements
          end
        end
      RUBY

      CONNECTION_STATE_RBS = <<~'RBS'.chomp
        interface _PgConnection
          def backend_pid: () -> Integer
        end

        module ConnectionState : _PgConnection
          @prepared_statements: Set[String]
          @prepared_statements_pid: Integer

          def prepared_statements: () -> Set[String]
        end
      RBS

      INITIALIZE = <<~'RUBY'.chomp
        # db: a ConnectionPool (or anything that responds to #with and yields a PG::Connection).
        # logger: optional, anything with #debug (Logger, Rails.logger); logs the name and duration of every query.
        def initialize(db, logger: nil)
          @db = db
          @logger = logger
        end
      RUBY

      CONNECT = <<~'RUBY'.chomp
        # Opens a pool of connections: QuerySql.connect({ dbname: 'app' }, size: 5, timeout: 5, logger: Logger.new($stdout))
        # (pool_options go to ConnectionPool.new). To share an existing pool use QuerySql.new(pool).
        def self.connect(pg_params, logger: nil, **pool_options)
          new(ConnectionPool.new(**pool_options) { PG.connect(**pg_params) }, logger: logger)
        end
      RUBY

      TRANSACTION = <<~'RUBY'.chomp
        # Runs the block in a transaction on one connection and returns its value: COMMIT when the block returns
        # (also through break / return / throw), ROLLBACK when it raises or the thread is killed. A nested call
        # becomes a SAVEPOINT. Yields self, bound to that connection.
        def transaction(isolation: nil)
          with_client('transaction') do |client|
            outermost = client.transaction_status == PG::PQTRANS_IDLE
            raise ArgumentError, 'isolation: cannot be set on a nested transaction' if isolation && !outermost

            savepoint = outermost ? nil : "sqlc_sp_#{rand(0xffff_ffff).to_s(16)}"
            if outermost
              client.exec(isolation ? "BEGIN ISOLATION LEVEL #{ISOLATION_LEVELS.fetch(isolation)}" : 'BEGIN')
            else
              client.exec("SAVEPOINT #{savepoint}")
            end
            rollback = outermost ? 'ROLLBACK' : "ROLLBACK TO SAVEPOINT #{savepoint}"
            failed = false
            begin
              yield self
            rescue Exception # rubocop:disable Lint/RescueException
              failed = true
              client.exec(rollback)
              raise
            ensure
              unless failed
                # a statement failed and the block rescued the error: PostgreSQL can only roll back
                rescued = client.transaction_status == PG::PQTRANS_INERROR
                commit = outermost ? 'COMMIT' : "RELEASE SAVEPOINT #{savepoint}"
                client.exec(rescued || Thread.current.status == 'aborting' ? rollback : commit)
                client.exec("RELEASE SAVEPOINT #{savepoint}") if rescued && savepoint
                raise PG::InFailedSqlTransaction, 'transaction rolled back: a statement in it failed' if rescued && Thread.current.status != 'aborting'
              end
            end
          end
        end
      RUBY

      WITH_CLIENT = <<~'RUBY'.chomp
        def with_client(name)
          instrument(name) do
            @db.with do |client|
              client.reset if client.status == PG::CONNECTION_BAD # closed by the server (restart, failover, killed)
              configure(client) unless client.is_a?(ConnectionState)
              yield client
            end
          end
        end
      RUBY

      CONFIGURE = <<~'RUBY'.chomp
        # Connections of an injected pool are set up on first use: typed results and Ruby arrays as parameters.
        def configure(client)
          type_map = PG::BasicTypeMapForResults.new(client)
          type_map.default_type_map = string_arrays(client) # uuid, enums, money, ... come back as Strings
          client.type_map_for_results = type_map
          queries = PG::BasicTypeMapForQueries.new(client)
          # true / false as text ('t' / 'f'), also valid in COPY (the default binary encoder is not)
          queries[TrueClass] = queries[FalseClass] = PG::TextEncoder::Boolean.new(oid: 16)
          client.type_map_for_queries = queries
          client.extend(ConnectionState)
        end

        # Arrays of types without a decoder (uuid[], enum[], ...) become Arrays of Strings, other types Strings.
        def string_arrays(client)
          strings = PG::TypeMapAllStrings.new
          arrays = PG::TypeMapByOid.new
          client.exec("SELECT oid, typdelim FROM pg_type WHERE typcategory = 'A'", [], 0, strings).each do |row|
            arrays.add_coder(PG::TextDecoder::Array.new(oid: row['oid'].to_i, delimiter: row['typdelim'],
                                                        elements_type: PG::TextDecoder::String.new))
          end
          arrays.default_type_map = strings
          arrays
        end
      RUBY

      private

      def driver_gems = %w[pg]

      def encoder_for(column)
        return nil if column.is_sqlc_slice

        type = normalize_type(column.type.name)
        if column.is_array
          ['encode_array', ({ 'bytea' => 'bytea', 'json' => 'json', 'jsonb' => 'json' }[type])]
        elsif type == 'bytea' then ['encode_bytea']
        elsif %w[json jsonb].include?(type) then ['encode_json']
        elsif column_type(column, fallback: nil) == 'Float' then ['encode_float']
        end
      end

      def column_mappings
        # Ruby classes as returned by the pg gem with PG::BasicTypeMapForResults (verified by tests/end2end_pg.rb);
        # types without a decoder (uuid, money, interval, enums, ...) come back as Strings.
        @column_mappings ||= [
          mapping('bool', %w[bool boolean]),
          mapping('String', %w[char bpchar varchar text time uuid money macaddr macaddr8 interval xml name citext
                               bit varbit bytea tinytext mediumtext longtext tinyblob blob mediumblob longblob
                               binary varbinary timetz tsvector tsquery hstore ltree lquery ltxtquery
                               point line lseg box path polygon circle int4range int8range numrange tsrange
                               tstzrange daterange int4multirange int8multirange nummultirange tsmultirange
                               tstzmultirange datemultirange regclass regproc regtype pg_lsn int2vector oidvector
                               tid xid cid]),
          mapping('Integer', %w[int2 int4 int8 serial bigserial integer smallint bigint int smallserial oid]),
          mapping('Float', %w[float4 float8 real double]),
          mapping('BigDecimal', %w[numeric decimal]),
          mapping('Date', %w[date]),
          mapping('Time', %w[timestamp timestamptz datetime]),
          mapping('IPAddr', %w[inet cidr]),
          mapping('untyped', %w[json jsonb any anyelement anyarray record void unknown])
        ]
      end
    end
  end
end
