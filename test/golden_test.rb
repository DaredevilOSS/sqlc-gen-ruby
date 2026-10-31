# frozen_string_literal: true

require_relative 'test_helper'

# Diffs the generated files against the C# plugin's output checked in under examples/.
class GoldenTest < Minitest::Test
  include PluginHelper

  {
    'pg' => 'pg',
    'mysql2' => 'mysql2',
    'sqlite3' => 'sqlite3'
  }.each do |driver, example|
    %w[query_sql.rb query_sql.rbs].each do |name|
      define_method("test_#{driver}_#{name.tr('.', '_')}_matches_csharp_output") do
        files = generate(load_request(driver))
        expected = File.read(File.join(ROOT, 'examples', example, name))
        assert_equal normalize(expected), normalize(files.fetch(name))
      end
    end
  end
end
