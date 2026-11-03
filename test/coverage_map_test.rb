# frozen_string_literal: true

require_relative 'test_helper'

class CoverageMapTest < Minitest::Test
  def test_every_linked_test_method_exists
    root = File.expand_path('..', __dir__)
    coverage = File.read(File.join(root, 'docs/Coverage.md'))
    references = coverage.scan(/\]\(\.\.\/((?:tests|test)\/[^)#]+\.rb)#(test_[a-z0-9_]+)\)/)
    refute_empty references
    missing = references.filter_map do |file, method|
      source = File.read(File.join(root, file))
      "#{file}##{method}" unless source.match?(/\bdef #{Regexp.escape(method)}(?:\s|\()/)
    end
    assert_empty missing, "missing coverage methods: #{missing.join(', ')}"
  end
end
