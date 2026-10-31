# frozen_string_literal: true

require_relative 'test_helper'

# Snapshots of the C# plugin's output (recorded while it still existed) for the sqlc-captured queries plus
# synthetic ones (5+ params/columns, lower-case names, several query files) under different options:
# Ruby 3.1 (Struct) / 3.2 / generateGemfile / generateTypes=false.
class ExtendedGoldenTest < Minitest::Test
  include PluginHelper

  GOLDEN = File.join(PluginHelper::ROOT, 'test/golden')

  Dir.glob(File.join(GOLDEN, '*/*/')).sort.each do |dir|
    driver_case = File.basename(File.dirname(dir))
    variant = File.basename(dir)
    define_method("test_#{driver_case}_#{variant}") do
      options = JSON.parse(File.read(File.join(dir, 'options.json')))
      files = generate(load_request(driver_case, **options.transform_keys(&:to_sym)))
      expected = Dir.children(dir).reject { |f| f == 'options.json' }.sort
      assert_equal expected, files.keys.sort
      expected.each { |name| assert_equal File.binread(File.join(dir, name)), files.fetch(name), name }
    end
  end
end
