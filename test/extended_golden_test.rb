# frozen_string_literal: true

require_relative 'test_helper'
require_relative 'synthetic_requests'

# Snapshots of the plugin's output for the sqlc-captured queries plus synthetic ones, under different options:
# Ruby 3.1 (Struct) / 3.2 / generateGemfile / generateTypes=false. Review the diff when they change:
#   UPDATE_GOLDEN=1 ruby -Itest test/extended_golden_test.rb
class ExtendedGoldenTest < Minitest::Test
  include PluginHelper

  GOLDEN = File.join(PluginHelper::ROOT, 'test/golden')
  VARIANTS = {
    'default' => {},
    'ruby31_gemfile' => { rubyVersion: '3.1', generateGemfile: true },
    'ruby32_notypes' => { rubyVersion: '3.2', generateTypes: false }
  }.freeze

  %w[pg mysql2 sqlite3].product(VARIANTS.to_a).each do |driver, (variant, options)|
    define_method("test_#{driver}_extended_#{variant}") do
      dir = File.join(GOLDEN, driver, variant)
      files = generate(SyntheticRequests.extended_request(driver, **options))
      if ENV['UPDATE_GOLDEN']
        FileUtils.rm_rf(dir)
        FileUtils.mkdir_p(dir)
        files.each { |name, contents| File.binwrite(File.join(dir, name), contents) }
      end
      assert_equal Dir.children(dir).sort, files.keys.sort
      files.each { |name, contents| assert_equal File.binread(File.join(dir, name)), contents, "#{dir}/#{name}" }
    end
  end
end
