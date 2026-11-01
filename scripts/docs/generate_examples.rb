#!/usr/bin/env ruby
# frozen_string_literal: true

# Regenerates docs/Examples.md from the sqlc config (one section per `sql:` block).
#   ruby scripts/docs/generate_examples.rb docs/Examples.md
require 'yaml'

doc_file = ARGV.fetch(0)
config = YAML.safe_load_file(File.expand_path('../../sqlc.ci.yaml', __dir__))

def yaml_value(value) = value.is_a?(String) && value.match?(/\A[\d.]+\z/) ? %("#{value}") : value

sections = config['sql'].map do |sql|
  options = sql['codegen'].first['options']
  driver = options['driver']
  yaml = options.map { |key, value| "#{key}: #{yaml_value(value)}" }.join("\n")
  [
    "## Engine `#{sql['engine']}`: [examples/#{driver}](../examples/#{driver})",
    '',
    "### [Schema](../#{sql['schema']}) | [Queries](../#{sql['queries']}) | [End2End Test](../tests/end2end_#{driver}.rb)",
    '',
    '### Config',
    '```yaml',
    yaml,
    '```',
    ''
  ].join("\n")
end

File.write(doc_file, "# Examples\n#{sections.join("\n")}")
