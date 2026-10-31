#!/usr/bin/env ruby
require 'rake'
require 'rake/testtask'

# Plugin unit + golden tests (pure Ruby, no databases needed).
Rake::TestTask.new(:test) do |t|
  t.libs << 'test'
  t.pattern = 'test/*_test.rb'
end

Rake::TestTask.new(:end2end_tests) do |t| # called inside Docker
  t.pattern = 'tests/end2end_*.rb'
end

task :rubocop do
  sh 'bundle exec rubocop examples'
end

task :steep do
  sh 'bundle exec steep check --with-expectations'
end

task :run_end2end_tests do
  sh './scripts/tests/run_end2end.sh'
end

task :run_tests => [:run_end2end_tests]

# --- Process plugin (exe/plugin.rb run directly by sqlc) ---
task :sqlc_generate_process do
  sh 'sqlc -f sqlc.local.yaml generate'
end

task :test_process_plugin => [:test, :sqlc_generate_process, :run_tests]

# --- WASM plugin (dist/plugin.wasm: ruby.wasm interpreter + this plugin, see scripts/wasm/build.sh) ---
task :wasm_build do
  sh './scripts/wasm/build.sh'
end

task :update_wasm_plugin do
  sh './scripts/wasm/update_sha.sh sqlc.ci.yaml'
end

task :sqlc_generate_wasm => [:wasm_build, :update_wasm_plugin] do
  ENV['SQLCCACHE'] = './'
  sh 'sqlc -f sqlc.ci.yaml generate'
end

task :test_wasm_plugin => [:test, :sqlc_generate_wasm, :update_wasm_plugin, :run_tests]
