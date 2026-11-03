# frozen_string_literal: true

require 'json'
require_relative 'ruby_version'

module SqlcGenRuby
  # Port of PluginOptions/Options.cs + RawOptions.cs: parses the JSON `options:` block of the sqlc config.
  class Options
    DRIVERS = %w[mysql2 pg sqlite3].freeze
    KNOWN = %w[driver generateGemfile generateTypes rubyVersion overrides moduleName preparedStatements rename
               exactTableNames].freeze
    OVERRIDE_KEYS = %w[column db_type ruby_type].freeze

    # `overrides:` entry, matched by `column:` ("<QueryName>:<column>", "*:<column>", "<table>.<column>",
    # "<schema>.<table>.<column>") or `db_type:`; type/not_null come from `ruby_type:`
    Override = Struct.new(:query, :column, :type, :not_null, :table, :schema, :db_type, keyword_init: true)

    attr_reader :driver_name, :ruby_version, :generate_gemfile, :generate_types, :overrides, :module_name,
                :prepared_statements, :rename, :exact_table_names

    # global_options_bytes: the plugin's entry of the top-level `options:` of sqlc.yaml; per-codegen options win,
    # overrides of both apply (per-codegen first).
    def initialize(plugin_options_bytes, global_options_bytes = nil)
      raw = parse_object(plugin_options_bytes, 'plugin options')
      global = parse_object(global_options_bytes, 'global options')
      reject_unknown(global, 'global options')
      reject_unknown(raw, 'plugin options')
      raw = global.merge(raw).merge('overrides' => raw.fetch('overrides', []) + global.fetch('overrides', []),
                                    'rename' => global.fetch('rename', {}).merge(raw.fetch('rename', {})))

      @driver_name = fetch_string(raw, 'driver', required: true).downcase
      raise ArgumentError, "unknown driver: #{raw['driver']}" unless DRIVERS.include?(@driver_name)

      @generate_gemfile = fetch_bool(raw, 'generateGemfile', false) # not generating Gemfile by default
      @generate_types = fetch_bool(raw, 'generateTypes', true)
      @ruby_version = RubyVersion.parse(fetch_string(raw, 'rubyVersion', default: '3.3'))
      @overrides = parse_overrides(raw.fetch('overrides', []))
      @module_name = raw.key?('moduleName') ? fetch_module_name(raw) : nil # default: <Driver>Codegen
      @prepared_statements = fetch_bool(raw, 'preparedStatements', true)
      @rename = parse_rename(raw['rename'])
      @exact_table_names = fetch_bool(raw, 'exactTableNames', false)
      if raw.key?('preparedStatements') && @driver_name != 'pg'
        raise ArgumentError, 'option preparedStatements is only supported by the pg driver'
      end
    end

    # The override for a result column / parameter of a query (query_name nil for model columns); the first match of
    # "Query:col", "table.col", "*:col", db_type wins. table: Identifier of the column's table, if known.
    def override_for(query_name, column, table: column.table)
      name = column.name
      overrides.find { |o| o.query && o.query == query_name && o.column == name } ||
        overrides.find { |o| o.table && table && o.table == table.name && o.column == name && schema_match?(o, table) } ||
        overrides.find { |o| o.query == '*' && o.column == name } ||
        overrides.find { |o| o.db_type && o.db_type == normalize_db_type(column.type&.name) }
    end

    private

    def schema_match?(override, table) = override.schema.nil? || override.schema == table.schema.to_s

    def normalize_db_type(name) = name.to_s.downcase.delete_prefix('pg_catalog.')

    def parse_object(bytes, label)
      text = bytes.to_s.dup.force_encoding(Encoding::UTF_8)
      return {} if text.strip.empty? && label != 'plugin options'

      raw = JSON.parse(text)
      raise ArgumentError, "#{label} must be a JSON object" unless raw.is_a?(Hash)

      raw
    end

    def reject_unknown(raw, label)
      unknown = raw.keys - KNOWN
      return if unknown.empty?

      hints = unknown.map do |key|
        near = KNOWN.find { |k| k.casecmp?(key) || k.casecmp?(key.delete('_')) }
        near ? "#{key} (did you mean #{near}?)" : key
      end
      raise ArgumentError, "unknown #{label}: #{hints.join(', ')}; supported: #{KNOWN.join(', ')}"
    end

    # rename: { "authors": "Writer", "bio": "biography" } - table name -> model class, column name -> attribute
    def parse_rename(value)
      raise ArgumentError, 'option rename must be an object' unless value.is_a?(Hash)

      value.each do |key, name|
        raise ArgumentError, "rename #{key} must be a string" unless name.is_a?(String) && !name.empty?
      end
      value
    end

    def parse_overrides(list)
      raise ArgumentError, 'option overrides must be a list' unless list.is_a?(Array)

      list.map do |entry|
        raise ArgumentError, 'each override must be an object' unless entry.is_a?(Hash)

        unknown = entry.keys - OVERRIDE_KEYS
        unless unknown.empty?
          hints = unknown.map { |key| (near = OVERRIDE_KEYS.find { |k| k.start_with?(key[0, 3]) }) ? "#{key} (did you mean #{near}?)" : key }
          raise ArgumentError, "unknown override keys: #{hints.join(', ')}; supported: #{OVERRIDE_KEYS.join(', ')}"
        end

        label = entry['column'] || entry['db_type']
        type = entry['ruby_type']
        raise ArgumentError, "override #{label} needs ruby_type.type" unless type.is_a?(Hash) && type['type'].is_a?(String)

        not_null = type['notNull']
        raise ArgumentError, "override #{label}: notNull must be a boolean" unless [nil, true, false].include?(not_null)

        override_target(entry).tap do |o|
          o.type = type['type']
          o.not_null = not_null
        end
      end
    end

    def override_target(entry)
      if entry.key?('db_type')
        return Override.new(db_type: normalize_db_type(entry['db_type'])) if entry['db_type'].is_a?(String)

        raise ArgumentError, 'override db_type must be a string'
      end
      spec = entry['column'].to_s
      if spec.include?(':')
        query, column = spec.split(':', 2)
        return Override.new(query: query, column: column) unless query.empty? || column.empty?
      else
        *schema, table, column = spec.split('.')
        return Override.new(table: table, column: column, schema: schema.first) if column && schema.size <= 1
      end
      raise ArgumentError, "override column must look like '<query>:<column>', '*:<column>' or '<table>.<column>', " \
                           "got #{spec.inspect}"
    end

    def fetch_string(raw, key, default: nil, required: false)
      raise ArgumentError, "missing required option: #{key}" if required && !raw.key?(key)

      value = raw.fetch(key, default)
      raise ArgumentError, "option #{key} must be a string" unless value.is_a?(String)

      value
    end

    def fetch_module_name(raw)
      name = fetch_string(raw, 'moduleName')
      unless name.match?(/\A[A-Z]\w*(::[A-Z]\w*)*\z/)
        raise ArgumentError, "option moduleName must be a Ruby constant path (e.g. MyApp::Db), got #{name.inspect}"
      end

      name
    end

    def fetch_bool(raw, key, default)
      value = raw.fetch(key, default)
      raise ArgumentError, "option #{key} must be a boolean" unless [true, false].include?(value)

      value
    end
  end
end
