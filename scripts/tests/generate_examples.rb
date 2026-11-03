#!/usr/bin/env ruby
# frozen_string_literal: true

require 'fileutils'
require 'yaml'

ruby_version, config_path = ARGV
abort "usage: #{$PROGRAM_NAME} <rubyVersion> [sqlc config]" unless ruby_version

root = File.expand_path('../..', __dir__)
config_path = File.expand_path(config_path || 'sqlc.local.yaml', root)
config_dir = File.dirname(config_path)
scratch = File.expand_path(".examples-ruby-#{ruby_version}", root)
unless scratch.start_with?("#{root}/.examples-ruby-") && File.basename(scratch).match?(/\A\.examples-ruby-[\d.]+\z/)
  abort "refusing to generate outside an examples scratch directory: #{scratch}"
end

FileUtils.rm_rf(scratch)
FileUtils.mkdir_p(scratch)
config = YAML.safe_load_file(config_path)
config.fetch('sql').each do |sql|
  codegen = sql.fetch('codegen').first
  codegen['out'] = File.join(File.basename(scratch), codegen.fetch('options').fetch('driver'))
  codegen.fetch('options')['rubyVersion'] = ruby_version
end

tmp_config = File.join(config_dir, ".generate-examples.#{Process.pid}.yaml")
begin
  File.write(tmp_config, config.to_yaml)
  system('sqlc', '-f', tmp_config, 'generate') || abort('sqlc generate failed')
ensure
  FileUtils.rm_f(tmp_config)
end

puts "EXAMPLES_DIR=#{scratch}"
