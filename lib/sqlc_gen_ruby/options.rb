# frozen_string_literal: true

require 'json'
require_relative 'ruby_version'

module SqlcGenRuby
  # Port of PluginOptions/Options.cs + RawOptions.cs: parses the JSON `options:` block of the sqlc config.
  class Options
    DRIVERS = %w[mysql2 pg sqlite3].freeze

    # `overrides:` entry - column is "<QueryName>:<column>" or "*:<column>"; type/not_null come from `ruby_type:`
    Override = Struct.new(:query, :column, :type, :not_null)

    attr_reader :driver_name, :ruby_version, :generate_gemfile, :generate_types, :overrides, :module_name,
                :prepared_statements

    def initialize(plugin_options_bytes)
      text = plugin_options_bytes.to_s.dup.force_encoding(Encoding::UTF_8)
      raw = JSON.parse(text)
      raise ArgumentError, 'plugin options must be a JSON object' unless raw.is_a?(Hash)

      @driver_name = fetch_string(raw, 'driver', required: true).downcase
      raise ArgumentError, "unknown driver: #{raw['driver']}" unless DRIVERS.include?(@driver_name)

      @generate_gemfile = fetch_bool(raw, 'generateGemfile', false) # not generating Gemfile by default
      @generate_types = fetch_bool(raw, 'generateTypes', true)
      @ruby_version = RubyVersion.parse(fetch_string(raw, 'rubyVersion', default: '3.3'))
      @overrides = parse_overrides(raw.fetch('overrides', []))
      @module_name = raw.key?('moduleName') ? fetch_module_name(raw) : nil # default: <Driver>Codegen
      @prepared_statements = fetch_bool(raw, 'preparedStatements', true)
    end

    # The override matching a result column / parameter of a query: "Query:col" wins over "*:col".
    def override_for(query_name, column_name)
      overrides.find { |o| o.query == query_name && o.column == column_name } ||
        overrides.find { |o| o.query == '*' && o.column == column_name }
    end

    private

    def parse_overrides(list)
      raise ArgumentError, 'option overrides must be a list' unless list.is_a?(Array)

      list.map do |entry|
        raise ArgumentError, 'each override must be an object' unless entry.is_a?(Hash)

        query, column = entry['column'].to_s.split(':', 2)
        raise ArgumentError, "override column must look like '<query>:<column>' or '*:<column>'" if column.to_s.empty?

        type = entry['ruby_type']
        raise ArgumentError, "override #{entry['column']} needs ruby_type.type" unless type.is_a?(Hash) && type['type'].is_a?(String)

        not_null = type['notNull']
        unless [nil, true, false].include?(not_null)
          raise ArgumentError, "override #{entry['column']}: notNull must be a boolean"
        end

        Override.new(query, column, type['type'], not_null)
      end
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
