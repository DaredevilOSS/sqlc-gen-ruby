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
          [CONNECTION_STATE, "module ConnectionState\n  def prepared_statements: () -> Set[String]\nend"],
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
          [CONFIGURE, 'def configure: (untyped client) -> void']
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

      def exec_rows_lines(exec) = ["result = #{exec}", 'result.cmd_tuples']

      # PostgreSQL has no last insert id (use RETURNING).
      def exec_result_lines(exec) = ["result = #{exec}", 'ExecResult.new(result.cmd_tuples, nil)']

      # Relies on a user-written `RETURNING <id>`.
      def exec_last_id_lines(exec, query)
        if query.columns.empty?
          raise ArgumentError, "#{query.name}: :execlastid on PostgreSQL needs a RETURNING clause"
        end

        ["result = #{exec}", "result.first['#{query.columns.first.name}']"]
      end

      # COPY ... FROM STDIN, one row at a time through the pg gem's CopyRow encoder.
      def copy_from_lines(rows_var, table, columns, attrs, _label)
        put = Code.block("#{rows_var}.each do |row|",
                         "client.put_copy_data([#{attrs.map { |a| "row.#{a}" }.join(', ')}])")
        [
          'encoder = PG::TextEncoder::CopyRow.new(type_map: client.type_map_for_queries)',
          Code.block("client.copy_data('COPY #{table} (#{columns.join(', ')}) FROM STDIN', encoder) do", put),
          'nil'
        ]
      end

      CONNECTION_STATE = <<~'RUBY'.chomp
        # State kept on every PG::Connection the first time it is used.
        module ConnectionState
          def prepared_statements
            @prepared_statements ||= Set[]
          end
        end
      RUBY

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
        # Runs the block in a transaction on one connection and returns its value: COMMIT when the block returns,
        # ROLLBACK when it raises. A nested call becomes a SAVEPOINT. Yields self, bound to that connection.
        def transaction(isolation: nil)
          with_client('transaction') do |client|
            outermost = client.transaction_status == PG::PQTRANS_IDLE
            savepoint = outermost ? nil : "sqlc_sp_#{rand(0xffff_ffff).to_s(16)}"
            if outermost
              client.exec(isolation ? "BEGIN ISOLATION LEVEL #{ISOLATION_LEVELS.fetch(isolation)}" : 'BEGIN')
            else
              client.exec("SAVEPOINT #{savepoint}")
            end
            begin
              result = yield self
              client.exec(outermost ? 'COMMIT' : "RELEASE SAVEPOINT #{savepoint}")
              result
            rescue Exception # rubocop:disable Lint/RescueException
              client.exec(outermost ? 'ROLLBACK' : "ROLLBACK TO SAVEPOINT #{savepoint}")
              raise
            end
          end
        end
      RUBY

      WITH_CLIENT = <<~'RUBY'.chomp
        def with_client(name)
          instrument(name) do
            @db.with do |client|
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
          # uuid, enums, money, ... come back as Strings, arrays of them (uuid[], enum[], ...) as Arrays of Strings
          fallback = PG::TypeMapByOid.new
          client.exec("SELECT oid FROM pg_type WHERE typcategory = 'A'").each do |row|
            fallback.add_coder(PG::TextDecoder::Array.new(oid: row['oid'].to_i, elements_type: PG::TextDecoder::String.new))
          end
          fallback.default_type_map = PG::TypeMapAllStrings.new
          type_map.default_type_map = fallback
          client.type_map_for_results = type_map
          client.type_map_for_queries = PG::BasicTypeMapForQueries.new(client)
          client.extend(ConnectionState)
        end
      RUBY

      private

      def driver_gems = %w[pg]

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
