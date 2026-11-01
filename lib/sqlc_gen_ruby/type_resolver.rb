# frozen_string_literal: true

module SqlcGenRuby
  # Full RBS type of a result column / parameter: DB type mapping (driver) + array + nullability + `overrides:`.
  class TypeResolver
    def initialize(driver, options)
      @driver = driver
      @options = options
    end

    # query_name: used to look up `overrides:` entries; nil for model (table) columns.
    # fallback: see Drivers::Base#column_type.
    def type(column, query_name: nil, fallback: :raise)
      override = query_name && @options.override_for(query_name, column.name)
      base = override ? override.type : @driver.column_type(column, fallback: fallback)
      base = "Array[#{base}]" if column.is_array && !override
      not_null?(column, override) || base == 'untyped' ? base : "#{base}?"
    end

    def nullable?(column, query_name)
      !not_null?(column, @options.override_for(query_name, column.name)) && !column.is_sqlc_slice
    end

    # A sqlc.slice parameter is passed as an Array of the element type.
    def slice_type(column, query_name)
      override = @options.override_for(query_name, column.name)
      "Array[#{override ? override.type : @driver.column_type(column)}]"
    end

    private

    def not_null?(column, override)
      override&.not_null.nil? ? column.not_null : override.not_null
    end
  end
end
