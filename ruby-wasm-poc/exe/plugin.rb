# frozen_string_literal: true

# sqlc plugin entry point: GenerateRequest on stdin -> GenerateResponse on stdout.
$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))
require 'sqlc_gen_ruby/generator'

$stdin.binmode
$stdout.binmode
request = SqlcGenRuby::Plugin::GenerateRequest.decode($stdin.read)
response = SqlcGenRuby::Generator.new.generate(request)
$stdout.write(response.encode)
