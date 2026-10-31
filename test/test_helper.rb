# frozen_string_literal: true

require 'open3'
require 'json'
require 'minitest/autorun'
$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))
require 'sqlc_gen_ruby/plugin_pb'

# Helpers to run the real plugin entry point as a subprocess over stdin/stdout, exactly like sqlc does.
module PluginHelper
  ROOT = File.expand_path('..', __dir__)
  PLUGIN = File.join(ROOT, 'exe/plugin.rb')
  FIXTURES = File.join(ROOT, 'test/fixtures')
  Plugin = SqlcGenRuby::Plugin

  # Real GenerateRequest bytes captured from `sqlc generate` (see scripts/capture_request.rb).
  def load_request(driver, **options)
    request = Plugin::GenerateRequest.decode(File.binread(File.join(FIXTURES, "#{driver}.bin")))
    unless options.empty?
      merged = JSON.parse(request.plugin_options).merge(options.transform_keys(&:to_s))
      request.plugin_options = JSON.generate(merged)
    end
    request
  end

  def run_plugin(request_bytes)
    out, err, status = Open3.capture3(RbConfig.ruby, PLUGIN, stdin_data: request_bytes, binmode: true)
    [out, err, status]
  end

  # Returns { 'name' => contents } or raises with the plugin's stderr.
  def generate(request)
    out, err, status = run_plugin(request.encode)
    raise "plugin failed: #{err}" unless status.success?

    Plugin::GenerateResponse.decode(out).files.to_h { |f| [f.name, f.contents.dup.force_encoding('UTF-8')] }
  end

  # The C# plugin's checked-in output contains a few CRs from CRLF line endings in its source.
  def normalize(text) = text.delete("\r").strip
end
