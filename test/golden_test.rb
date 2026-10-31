# frozen_string_literal: true

require_relative 'test_helper'

# examples/<driver> is the output of the plugin for the example schemas in examples/authors (real sqlc requests
# captured in test/fixtures). This test fails when the checked-in examples are stale: regenerate them with
# `sqlc generate` (CI runs `sqlc diff` for the same purpose).
class GoldenTest < Minitest::Test
  include PluginHelper

  { 'pg' => 'pg', 'mysql2' => 'mysql2', 'sqlite3' => 'sqlite3' }.each do |driver, example|
    define_method("test_#{driver}_matches_examples") do
      files = generate(load_request(driver))
      assert_equal %w[models.rb models.rbs query_sql.rb query_sql.rbs], files.keys.sort
      files.each do |name, contents|
        expected = File.read(File.join(ROOT, 'examples', example, name))
        assert_equal normalize(expected), normalize(contents), "examples/#{example}/#{name} is stale"
      end
    end
  end
end
