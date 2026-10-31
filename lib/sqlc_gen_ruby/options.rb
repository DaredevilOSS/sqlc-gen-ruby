# frozen_string_literal: true

require 'json'
require_relative 'ruby_version'

module SqlcGenRuby
  # Port of PluginOptions/Options.cs + RawOptions.cs: parses the JSON `options:` block of the sqlc config.
  class Options
    DRIVERS = %w[mysql2 pg sqlite3].freeze

    attr_reader :driver_name, :ruby_version, :generate_gemfile, :generate_types

    def initialize(plugin_options_bytes)
      text = plugin_options_bytes.to_s.dup.force_encoding(Encoding::UTF_8)
      raw = JSON.parse(text)
      raise ArgumentError, 'plugin options must be a JSON object' unless raw.is_a?(Hash)

      @driver_name = fetch_string(raw, 'driver', required: true).downcase
      raise ArgumentError, "unknown driver: #{raw['driver']}" unless DRIVERS.include?(@driver_name)

      @generate_gemfile = fetch_bool(raw, 'generateGemfile', false) # not generating Gemfile by default
      @generate_types = fetch_bool(raw, 'generateTypes', true)
      @ruby_version = RubyVersion.parse(fetch_string(raw, 'rubyVersion', default: '3.3'))
    end

    private

    def fetch_string(raw, key, default: nil, required: false)
      raise ArgumentError, "missing required option: #{key}" if required && !raw.key?(key)

      value = raw.fetch(key, default)
      raise ArgumentError, "option #{key} must be a string" unless value.is_a?(String)

      value
    end

    def fetch_bool(raw, key, default)
      value = raw.fetch(key, default)
      raise ArgumentError, "option #{key} must be a boolean" unless [true, false].include?(value)

      value
    end
  end
end
