#!/usr/bin/env ruby
# frozen_string_literal: true

# Regenerates docs/Examples.md from the sqlc config (one section per `sql:` block).
#   ruby scripts/docs/generate_examples.rb docs/Examples.md
require 'yaml'

doc_file = ARGV.fetch(0)
config = YAML.safe_load_file(File.expand_path('../../sqlc.ci.yaml', __dir__))

ENGINE_NAMES = { 'postgresql' => 'PostgreSQL', 'mysql' => 'MySQL', 'sqlite' => 'SQLite' }.freeze

def yaml_value(value) = value.is_a?(String) && value.match?(/\A[\d.]+\z/) ? %("#{value}") : value

sections = config['sql'].map do |sql|
  options = sql['codegen'].first['options']
  driver = options['driver']
  yaml = options.map { |key, value| "#{key}: #{yaml_value(value)}" }.join("\n")
  [
    "## #{ENGINE_NAMES.fetch(sql['engine'])} (`#{driver}`)",
    '',
    "[Schema](../#{sql['schema']}) · [Queries](../#{sql['queries']}) · [Generated code](../examples/#{driver}) · " \
      "[End-to-end tests](../tests/end2end_#{driver}.rb)",
    '',
    'Options:',
    '```yaml',
    yaml,
    '```',
    ''
  ].join("\n")
end

intro = <<~MARKDOWN
  # Examples

  The same example application for each database: a schema, queries that use every supported feature, and the code
  the plugin generates from them. The generated code is committed, and the end-to-end tests run against it.

  In each generated directory, `query_sql.rb` has the query methods, `models.rb` the table and enum models,
  `connection.rb` the shared helpers, and the `.rbs` files their signatures
  (see [The generated code](Generated-Code.md)).

MARKDOWN

File.write(doc_file, intro + sections.join("\n"))
