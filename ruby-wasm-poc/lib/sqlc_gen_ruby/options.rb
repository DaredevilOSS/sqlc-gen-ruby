# frozen_string_literal: true

require 'json'

module SqlcGenRuby
  class Options
    attr_reader :driver, :ruby_version, :generate_gemfile, :generate_types

    def initialize(plugin_options_bytes)
      text = plugin_options_bytes.to_s.dup.force_encoding(Encoding::UTF_8)
      raw = text.strip.empty? ? {} : JSON.parse(text)
      @driver = raw.fetch('driver')
      @generate_gemfile = raw.fetch('generateGemfile', false)
      @generate_types = raw.fetch('generateTypes', true)
      @ruby_version = Gem::Version.new(raw.fetch('rubyVersion', '3.3'))
    end

    def immutable_data_supported?
      ruby_version >= Gem::Version.new('3.2')
    end
  end
end
