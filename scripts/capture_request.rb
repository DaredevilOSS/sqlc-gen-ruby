#!/usr/bin/env ruby
# frozen_string_literal: true

# A sqlc *process plugin* that records the GenerateRequest sqlc sends it, to refresh test/fixtures/*.bin.
# What is kept is what sqlc sent (queries, plugin options, catalog) minus the settings and the built-in
# schemas (pg_catalog & co.), which are large and unused. The file is re-encoded by the plugin's own codec.
#
#   cat > /tmp/capture-pg.sh <<'SH'
#   #!/bin/sh
#   exec ruby /path/to/scripts/capture_request.rb /path/to/test/fixtures/pg.bin
#   SH
#   chmod +x /tmp/capture-pg.sh   # then point a sqlc process plugin `cmd:` at it and run `sqlc generate`
$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))
require 'sqlc_gen_ruby/catalog'
require 'sqlc_gen_ruby/plugin_pb'

request = SqlcGenRuby::Plugin::GenerateRequest.decode($stdin.binmode.read)
request.catalog.schemas.reject! { |s| SqlcGenRuby::Catalog::INTERNAL_SCHEMAS.include?(s.name) }
File.binwrite(ENV.fetch('FIXTURE_PATH') { ARGV.fetch(0) }, request.encode)
# sqlc expects a (possibly empty) GenerateResponse back
$stdout.binmode.write('')
