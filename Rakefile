#!/usr/bin/env ruby
require 'rake'
require 'rake/testtask'

Rake::TestTask.new(:end2end_tests) do |t| # called inside Docker
    t.pattern = "tests/end2end_*.rb" 
end

task :steep do
    sh "bundle exec steep check --with-expectations"
end

task :run_end2end_tests do
    sh "./scripts/tests/run_end2end.sh" 
end

task :run_tests => [:run_end2end_tests]

# Other
task :dotnet_format do
    sh "dotnet format --exclude GeneratedProtobuf"
end

task :protobuf_generate do
    sh "./scripts/generate_protobuf.sh"
end

task :dotnet_publish_process => [:protobuf_generate, :dotnet_format] do
    sh "dotnet publish LocalRunner -c release --output dist/"
end

task :sqlc_generate_process => [:dotnet_publish_process] do
    sh "sqlc -f sqlc.local.yaml generate"
end

task :test_process_plugin => [:sqlc_generate_process, :run_tests]

task :dotnet_publish_wasm => :protobuf_generate do
    sh "dotnet publish WasmRunner -c release --output dist/"
    sh "./scripts/wasm/copy_plugin_to.sh dist"
end

task :update_wasm_plugin do
    sh "./scripts/wasm/update_sha.sh sqlc.ci.yaml"
end

task :sqlc_generate_wasm => [:dotnet_publish_wasm, :update_wasm_plugin] do
    ENV['SQLCCACHE'] = './'
    sh "sqlc -f sqlc.ci.yaml generate"
end

task :test_wasm_plugin => [:sqlc_generate_wasm, :update_wasm_plugin, :run_tests]
