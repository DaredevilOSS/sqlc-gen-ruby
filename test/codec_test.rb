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

  # request encoded by the official gem -> plugin (own decoder) -> response decoded by both implementations
  def test_official_request_and_response_agree_with_own_codec
    out, err, status = run_plugin(Fixture.k('GenerateRequest').encode(Fixture.request))
    assert status.success?, err
    official = Fixture.k('GenerateResponse').decode(out).files.to_h { |f| [f.name, f.contents] }
    own = Plugin::GenerateResponse.decode(out).files.to_h { |f| [f.name, f.contents] }
    assert_equal official, own
    assert_includes own.keys, 'query_sql.rb'
    assert_includes own.fetch('query_sql.rb'), "GET_AUTHOR_SQL = <<~'SQL'\n    SELECT id, name, bio FROM authors"
  end

  def test_own_encoding_is_readable_by_the_official_implementation
    request = load_request('pg')
    # the official fixture schema only models a subset of the request; unknown fields must be skipped
    decoded = Fixture.k('GenerateRequest').decode(request.encode)
    assert_equal request.queries.map(&:name), decoded.queries.map(&:name)
    assert_equal request.queries.first.params.first.column.name, decoded.queries.first.params.first.column.name
  end
end
