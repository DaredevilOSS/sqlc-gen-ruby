# frozen_string_literal: true

# Runs the real plugin entry point (exe/plugin.rb) as a subprocess over stdin/stdout
# exactly the way sqlc runs it, then diffs the output with the C# plugin's output
# checked in under examples/pg.
require 'open3'
require 'minitest/autorun'
require_relative 'fixture'

class GoldenTest < Minitest::Test
  ROOT = File.expand_path('..', __dir__)
  EXAMPLES = File.expand_path('../../examples/pg', __dir__)

  def setup
    out, err, st = Open3.capture3('ruby', File.join(ROOT, 'exe/plugin.rb'),
                                  stdin_data: Fixture.k('GenerateRequest').encode(Fixture.request), binmode: true)
    assert st.success?, err
    @files = Fixture.k('GenerateResponse').decode(out).files.to_h { |f| [f.name, f.contents] }
  end

  def normalize(s) = s.delete("\r").strip

  %w[query_sql.rb query_sql.rbs].each do |name|
    define_method("test_#{name}_matches_csharp_output") do
      assert_equal normalize(File.read(File.join(EXAMPLES, name))), normalize(@files.fetch(name))
    end
  end
end
