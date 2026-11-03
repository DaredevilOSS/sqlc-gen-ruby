# frozen_string_literal: true

require_relative 'test_helper'
require 'sqlc_gen_ruby/options'

class OptionsTest < Minitest::Test
  Options = SqlcGenRuby::Options
  RubyVersion = SqlcGenRuby::RubyVersion

  def opts(hash) = Options.new(JSON.generate(hash))

  def test_defaults
    o = opts(driver: 'pg')
    assert_equal 'pg', o.driver_name
    assert_equal false, o.generate_gemfile
    assert_equal true, o.generate_types
    assert_equal '3.3', o.ruby_version.to_s
  end

  def test_driver_is_case_insensitive_and_validated
    assert_equal 'mysql2', opts(driver: 'Mysql2').driver_name
    assert_raises(ArgumentError) { opts(driver: 'oracle') }
    assert_raises(ArgumentError) { opts({}) }
  end

  def test_version_bounds
    %w[3.1 3.2 3.3 3.4 3].each { |v| RubyVersion.parse(v) }
    err = assert_raises(ArgumentError) { RubyVersion.parse('3.5') }
    assert_equal 'Provided version 3.5 exceeds max version 3.4', err.message
    err = assert_raises(ArgumentError) { RubyVersion.parse('3.0') }
    assert_equal 'Provided version 3.0 exceeds min version 3.1', err.message
    assert_raises(ArgumentError) { RubyVersion.parse('2.7') }
    assert_raises(ArgumentError) { RubyVersion.parse('three') }
    assert_raises(ArgumentError) { RubyVersion.parse('3.03') }
  end

  # The C# comparison treats a patch component as greater than a missing one.
  def test_patch_versions_compare_like_the_csharp_implementation
    assert_raises(ArgumentError) { RubyVersion.parse('3.4.1') }
    RubyVersion.parse('3.2.9')
  end

  def test_immutable_data_support
    refute RubyVersion.parse('3.1').immutable_data_supported?
    assert RubyVersion.parse('3.2').immutable_data_supported?
    assert RubyVersion.parse('3.3').immutable_data_supported?
    assert RubyVersion.parse(' 3.2 ').immutable_data_supported?
  end

  def test_option_types_are_validated
    assert_raises(ArgumentError) { opts(driver: 'pg', generateTypes: 'yes') }
    assert_raises(ArgumentError) { opts(driver: 'pg', rubyVersion: 3.3) }
  end
end
