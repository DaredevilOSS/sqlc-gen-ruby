# frozen_string_literal: true

require_relative 'code'

module SqlcGenRuby
  # Full RBS type of a result column / parameter: DB type mapping (driver) + array + nullability + `overrides:`.
  class TypeResolver
    def initialize(driver, options)
      @driver = driver
      @options = options
    end

    # query_name: used to look up `overrides:` entries; nil for model (table) columns, which pass their table.
    # fallback: see Drivers::Base#column_type.
    def type(column, query_name: nil, table: column.table, fallback: 'untyped')
      override = @options.override_for(query_name, column, table: table)
      base = override ? override.type : driver_type(column, query_name, fallback)
      # a db_type override names the element type; a column override the whole type
      base = array_of(base, column) if column.is_array && (override.nil? || override.db_type)
      not_null?(column, override) || base == 'untyped' ? base : "#{base}?"
    end

    def nullable?(column, query_name)
      !not_null?(column, @options.override_for(query_name, column)) && !column.is_sqlc_slice
    end

    # A sqlc.slice parameter is passed as an Array of the element type.
    def slice_type(column, query_name)
      override = @options.override_for(query_name, column)
      "Array[#{override ? override.type : driver_type(column, query_name, 'untyped')}]"
    end

    # Rows are Struct (keyword_init) before Ruby 3.2, Data from 3.2.
    def keyword_rows? = !@options.ruby_version.immutable_data_supported?

    def member_name(name) = Code.member_name(name, struct: keyword_rows?)

    private

    # int[][] -> Array[Array[Integer]] (sqlc sends array_dims; 0 from older versions means 1)
    def array_of(base, column)
      [column.array_dims.to_i, 1].max.times.reduce(base) { |type, _| "Array[#{type}]" }
    end

    def driver_type(column, query_name, fallback)
      @driver.column_type(column, fallback: fallback)
    rescue ArgumentError => e
      raise ArgumentError, "#{query_name || 'model'}: column #{column.name}: #{e.message}" if query_name

      raise
    end

    def not_null?(column, override)
      override&.not_null.nil? ? column.not_null : override.not_null
    end
  end
end
