# frozen_string_literal: true

# Cross-checks the plugin's hand-written protobuf codec against Google's official implementation
# (test-only dependency; the plugin itself is pure Ruby so it can run inside ruby.wasm).
begin
  require_relative 'official_protobuf'
rescue LoadError
  warn 'google-protobuf not installed - skipping codec cross-check'
  return
end
require_relative 'test_helper'

class CodecTest < Minitest::Test
  include PluginHelper

  def test_official_request_decodes_and_generates_same_output_as_captured_one
    official = Fixture.k('GenerateRequest').encode(Fixture.request)
    out, err, status = run_plugin(official)
    assert status.success?, err
    files = Fixture.k('GenerateResponse').decode(out).files.to_h { |f| [f.name, f.contents] }
    %w[query_sql.rb query_sql.rbs].each do |name|
      assert_equal normalize(File.read(File.join(ROOT, 'examples/pg', name))), normalize(files.fetch(name))
    end
  end

  def test_captured_sqlc_request_roundtrips_through_the_codec
    bytes = File.binread(File.join(FIXTURES, 'pg.bin'))
    decoded = Plugin::GenerateRequest.decode(bytes)
    official = Fixture.k('GenerateRequest').decode(Fixture.k('GenerateRequest').encode(Fixture.request))
    assert_equal official.queries.map(&:name), %w[GetAuthor ListAuthors CreateAuthor DeleteAuthor Test]
    refute_empty decoded.queries
    assert_equal decoded.queries.size, Plugin::GenerateRequest.decode(decoded.encode).queries.size
  end
end
