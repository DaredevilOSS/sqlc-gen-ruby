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
    %w[3.1 3.2 3.3 3].each { |v| RubyVersion.parse(v) }
    err = assert_raises(ArgumentError) { RubyVersion.parse('3.4') }
    assert_equal 'Provided version 3.4 exceeds max version 3.3', err.message
    err = assert_raises(ArgumentError) { RubyVersion.parse('3.0') }
    assert_equal 'Provided version 3.0 exceeds min version 3.1', err.message
    assert_raises(ArgumentError) { RubyVersion.parse('2.7') }
    assert_raises(ArgumentError) { RubyVersion.parse('three') }
    assert_raises(ArgumentError) { RubyVersion.parse('3.03') }
  end

  # The C# comparison treats a patch component as greater than a missing one.
  def test_patch_versions_compare_like_the_csharp_implementation
    assert_raises(ArgumentError) { RubyVersion.parse('3.3.1') }
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

  def test_unknown_options_are_rejected_with_a_hint
    error = assert_raises(ArgumentError) { opts(driver: 'pg', generate_types: false, emitJsonTags: true) }
    assert_includes error.message, 'unknown plugin options: generate_types (did you mean generateTypes?), emitJsonTags'
    error = assert_raises(ArgumentError) { Options.new(JSON.generate(driver: 'pg'), JSON.generate(typo: 1)) }
    assert_includes error.message, 'unknown global options: typo'
  end

  def test_override_forms
    o = opts(driver: 'pg', overrides: [{ column: 'public.authors.bio', ruby_type: { type: 'A' } },
                                       { db_type: 'pg_catalog.UUID', ruby_type: { type: 'B' } }])
    assert_equal [%w[authors bio public], 'uuid'], [o.overrides[0].to_h.values_at(:table, :column, :schema), o.overrides[1].db_type]
    assert_raises(ArgumentError) { opts(driver: 'pg', overrides: [{ column: 'a.b.c.d', ruby_type: { type: 'A' } }]) }
    assert_raises(ArgumentError) { opts(driver: 'pg', rename: { 'a' => 1 }) }
  end
end
