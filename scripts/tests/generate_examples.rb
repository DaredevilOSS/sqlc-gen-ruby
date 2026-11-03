#!/usr/bin/env ruby
# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'yaml'

ruby_version = ARGV.shift
abort "usage: #{$PROGRAM_NAME} <rubyVersion> [sqlc config] [--driver DRIVER] [--options JSON] [--generate-gemfile]" unless ruby_version

config_path = ARGV.first&.start_with?('--') ? nil : ARGV.shift
config_path ||= 'sqlc.local.yaml'
driver = nil
plugin_options = {}
generate_gemfile = false
until ARGV.empty?
  case ARGV.shift
  when '--driver'
    driver = ARGV.shift || abort('--driver requires a value')
  when '--options'
    plugin_options = JSON.parse(ARGV.shift || abort('--options requires a JSON object'))
    abort('--options must be a JSON object') unless plugin_options.is_a?(Hash)
  when '--generate-gemfile'
    generate_gemfile = true
  else
    abort "usage: #{$PROGRAM_NAME} <rubyVersion> [sqlc config] [--driver DRIVER] [--options JSON] [--generate-gemfile]"
  end
end

root = File.expand_path('../..', __dir__)
config_path = File.expand_path(config_path, root)
config_dir = File.dirname(config_path)
scratch = File.expand_path(".examples-ruby-#{ruby_version}", root)
unless scratch.start_with?("#{root}/.examples-ruby-") && File.basename(scratch).match?(/\A\.examples-ruby-[\d.]+\z/)
  abort "refusing to generate outside an examples scratch directory: #{scratch}"
end

FileUtils.rm_rf(scratch)
FileUtils.mkdir_p(scratch)
config = YAML.safe_load_file(config_path)
config['sql'] = config.fetch('sql').select do |sql|
  !driver || sql.fetch('codegen').first.fetch('options').fetch('driver') == driver
end
abort "no sql block found for driver #{driver}" if config['sql'].empty?
config.fetch('sql').each do |sql|
  codegen = sql.fetch('codegen').first
  codegen['out'] = File.join(File.basename(scratch), codegen.fetch('options').fetch('driver'))
  codegen.fetch('options').merge!(plugin_options)
  codegen.fetch('options').merge!('rubyVersion' => ruby_version, 'generateGemfile' => generate_gemfile)
end

tmp_config = File.join(config_dir, ".generate-examples.#{Process.pid}.yaml")
begin
  File.write(tmp_config, config.to_yaml)
  system('sqlc', '-f', tmp_config, 'generate') || abort('sqlc generate failed')
ensure
  FileUtils.rm_f(tmp_config)
end

puts "EXAMPLES_DIR=#{scratch}"
