#!/usr/bin/env ruby
# frozen_string_literal: true

# A sqlc *process plugin* that records the GenerateRequest sqlc sends it, to refresh test/fixtures/*.bin.
# The (large, unused) catalog field is stripped; every other byte is exactly what sqlc sent.
#
#   cat > /tmp/capture-pg.sh <<'SH'
#   #!/bin/sh
#   exec ruby /path/to/scripts/capture_request.rb /path/to/test/fixtures/pg.bin
#   SH
#   chmod +x /tmp/capture-pg.sh   # then point a sqlc process plugin `cmd:` at it and run `sqlc generate`
$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))
require 'sqlc_gen_ruby/proto'

CATALOG_FIELD = 2

data = $stdin.binmode.read
reader = SqlcGenRuby::Proto::Reader.new(data)
out = ''.b
until reader.eof?
  start = reader.pos
  number, wire = reader.read_tag
  reader.skip(wire)
  out << data.byteslice(start, reader.pos - start) unless number == CATALOG_FIELD
end
File.binwrite(ARGV.fetch(0), out)
# sqlc expects a (possibly empty) GenerateResponse back
$stdout.binmode.write('')
