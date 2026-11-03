#!/usr/bin/env ruby
# frozen_string_literal: true

require 'fileutils'
require 'rbconfig'
require 'yaml'

root = File.expand_path('../..', __dir__)
config_path = File.expand_path(ARGV.fetch(0, 'sqlc.local.yaml'), root)
config = YAML.safe_load_file(config_path)
capture = File.join(root, 'scripts/capture_request.rb')
drivers = config.fetch('sql').map { |sql| sql.fetch('codegen').first.fetch('options').fetch('driver') }.uniq
wrappers = {}

config['plugins'] = drivers.map do |driver|
  fixture = File.join(root, "test/fixtures/#{driver}.bin")
  wrapper = File.join(root, ".capture-request-#{driver}-#{Process.pid}")
  File.write(wrapper, "#!/usr/bin/env ruby\nexec #{[RbConfig.ruby, capture, fixture].map(&:dump).join(', ')}\n")
  FileUtils.chmod(0o755, wrapper)
  wrappers[driver] = wrapper
  {
    'name' => "capture-#{driver}",
    'process' => { 'cmd' => wrapper },
    'env' => ['PATH']
  }
end
config.fetch('sql').each do |sql|
  driver = sql.fetch('codegen').first.fetch('options').fetch('driver')
  sql.fetch('codegen').first['plugin'] = "capture-#{driver}"
end

tmp_config = File.join(File.dirname(config_path), ".capture-fixtures.#{Process.pid}.yaml")
begin
  File.write(tmp_config, config.to_yaml)
  system('sqlc', '-f', tmp_config, 'generate') || abort('sqlc fixture capture failed')
ensure
  File.delete(tmp_config) if File.exist?(tmp_config)
  wrappers.each_value { |wrapper| FileUtils.rm_f(wrapper) }
end
