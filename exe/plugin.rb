#!/usr/bin/env ruby
# frozen_string_literal: true

# sqlc plugin entry point: GenerateRequest on stdin -> GenerateResponse on stdout.
$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))
require 'sqlc_gen_ruby/generator'

$stdin.binmode
$stdout.binmode
begin
  request = SqlcGenRuby::Plugin::GenerateRequest.decode($stdin.read)
  response = SqlcGenRuby::Generator.new.generate(request)
  $stdout.write(response.encode)
rescue StandardError => e
  # sqlc shows the plugin's stderr when it exits non-zero.
  warn "sqlc-gen-ruby: #{e.class}: #{e.message}"
  warn e.backtrace.first(10).join("\n") if ENV['SQLC_GEN_RUBY_DEBUG']
  exit 1
end
