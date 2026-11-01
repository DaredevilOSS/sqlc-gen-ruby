# frozen_string_literal: true

require_relative 'code'

module SqlcGenRuby
  # How the columns of a query become attributes of its `<Query>Row` class.
  # Plain columns map 1:1; a `sqlc.embed(table)` column expands (in the SQL) to all columns of that table and becomes
  # one attribute holding the table's model, so such rows are read by position.
  class RowLayout
    # optional: an embedded table on the outer side of a join, nil when the join found no row
    Entry = Struct.new(:attr, :type, :column, :table, :optional)
    OUTER_JOIN = /\b(?:LEFT|RIGHT|FULL)\s+(?:OUTER\s+)?JOIN\b/i

    def initialize(driver, catalog, types)
      @driver = driver
      @catalog = catalog
      @types = types
      @cache = {}
    end

    def entries(query)
      @cache[query.object_id] ||= build(query)
    end

    # Names of result columns can be ambiguous (embed, joins), positions never are.
    def array_rows?(query)
      @driver.row_data_type == :array || query.columns.any? { |c| embed?(c) }
    end

    private

    def embed?(column) = !column.embed_table.nil? && !column.embed_table.name.empty?

    def build(query)
      taken = query.columns.reject { |c| embed?(c) }.map { |c| Code.attr_name(c.name) }
      # sqlc does not say which side of a join an embedded table is on: in an outer join any of them may be missing
      outer = query.text.match?(OUTER_JOIN)
      query.columns.map do |column|
        if embed?(column)
          table = @catalog.table_for(column.embed_table) or
            raise ArgumentError, "#{query.name}: sqlc.embed of unknown table #{column.embed_table.name}"
          name = unique_name(taken, Code.attr_name(Code.singularize(column.name)))
          Entry.new(name, outer ? "#{table.model_name}?" : table.model_name, column, table, outer)
        else
          Entry.new(Code.attr_name(column.name), @types.type(column, query_name: query.name), column, nil, false)
        end
      end.tap { |list| reject_duplicate_columns(query, list) }
    end

    # first `author`, then `author2`, `author3`, ... (only embedded tables are renamed)
    def unique_name(taken, base)
      name = base
      suffix = 1
      name = "#{base}#{suffix += 1}" while taken.include?(name)
      taken << name
      name
    end

    def reject_duplicate_columns(query, list)
      names = list.map(&:attr)
      dupes = names.tally.select { |_, n| n > 1 }.keys
      raise ArgumentError, "duplicate column names in #{query.name}Row: #{dupes.join(', ')}" unless dupes.empty?
    end
  end
end
