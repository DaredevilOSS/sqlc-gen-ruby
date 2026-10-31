# frozen_string_literal: true

# Builds a GenerateRequest equivalent to what sqlc would send for
# examples/authors/postgresql (hand-built, since sqlc isn't runnable here).
# Uses the official google-protobuf gem as an independent encoder so the
# plugin's pure-Ruby decoder is verified against a real protobuf implementation.
require 'google/protobuf'

module Fixture
  POOL = Google::Protobuf::DescriptorPool.generated_pool
  # Minimal schema mirroring sqlc's codegen.proto (same field numbers).
  require 'google/protobuf/descriptor_pb'
  fdp = Google::Protobuf::FileDescriptorProto.new(name: 'fx.proto', package: 'plugin', syntax: 'proto3')
  add = lambda do |name, fields|
    m = Google::Protobuf::DescriptorProto.new(name: name)
    fields.each do |fname, num, type, label, tname|
      m.field << Google::Protobuf::FieldDescriptorProto.new(
        name: fname, number: num, type: type, label: label || :LABEL_OPTIONAL, type_name: tname
      )
    end
    fdp.message_type << m
  end
  rep = :LABEL_REPEATED
  add.call('Identifier', [['catalog', 1, :TYPE_STRING], ['schema', 2, :TYPE_STRING], ['name', 3, :TYPE_STRING]])
  add.call('Column', [['name', 1, :TYPE_STRING], ['not_null', 3, :TYPE_BOOL], ['length', 6, :TYPE_INT32],
                      ['type', 12, :TYPE_MESSAGE, nil, '.plugin.Identifier']])
  add.call('Parameter', [['number', 1, :TYPE_INT32], ['column', 2, :TYPE_MESSAGE, nil, '.plugin.Column']])
  add.call('Query', [['text', 1, :TYPE_STRING], ['name', 2, :TYPE_STRING], ['cmd', 3, :TYPE_STRING],
                     ['columns', 4, :TYPE_MESSAGE, rep, '.plugin.Column'],
                     ['params', 5, :TYPE_MESSAGE, rep, '.plugin.Parameter'],
                     ['filename', 7, :TYPE_STRING]])
  add.call('Settings', [['version', 1, :TYPE_STRING], ['engine', 2, :TYPE_STRING]])
  add.call('GenerateRequest', [['settings', 1, :TYPE_MESSAGE, nil, '.plugin.Settings'],
                               ['queries', 3, :TYPE_MESSAGE, rep, '.plugin.Query'],
                               ['sqlc_version', 4, :TYPE_STRING], ['plugin_options', 5, :TYPE_BYTES]])
  add.call('OutFile', [['name', 1, :TYPE_STRING], ['contents', 2, :TYPE_BYTES]])
  add.call('GenerateResponse', [['files', 1, :TYPE_MESSAGE, rep, '.plugin.OutFile']])
  POOL.add_serialized_file(Google::Protobuf::FileDescriptorProto.encode(fdp))
  # Materialize every message class up front (repeated fields resolve element types lazily).
  fdp.message_type.each { |m| POOL.lookup("plugin.#{m.name}").msgclass }

  def self.k(name) = POOL.lookup("plugin.#{name}").msgclass

  def self.col(name, type)
    k('Column').new(name: name, not_null: true, type: k('Identifier').new(name: type))
  end

  AUTHORS = [col('id', 'bigserial'), col('name', 'text'), col('bio', 'text')].freeze
  TYPES = %w[c_bit:bit c_smallint:int2 c_boolean:bool c_integer:int4 c_bigint:int8 c_serial:serial
             c_decimal:decimal c_numeric:numeric c_real:float4 c_double_precision:float8 c_date:date
             c_time:time c_timestamp:timestamp c_char:bpchar c_varchar:varchar c_bytea:bytea c_text:text
             c_json:json].map { |s| col(*s.split(':')) }.freeze

  def self.param(n, c) = k('Parameter').new(number: n, column: c)

  def self.query(name, cmd, text, cols, params)
    k('Query').new(name: name, cmd: cmd, text: text, columns: cols, params: params, filename: 'query.sql')
  end

  def self.request
    qs = [
      query('GetAuthor', ':one', "SELECT id, name, bio FROM authors\nWHERE id = $1 LIMIT 1", AUTHORS, [param(1, AUTHORS[0])]),
      query('ListAuthors', ':many', "SELECT id, name, bio FROM authors\nORDER BY name", AUTHORS, []),
      query('CreateAuthor', ':one',
            "INSERT INTO authors (\n    name, bio\n) VALUES (\n    $1, $2\n)\nRETURNING id, name, bio", AUTHORS,
            [param(1, AUTHORS[1]), param(2, AUTHORS[2])]),
      query('DeleteAuthor', ':exec', "DELETE FROM authors\nWHERE id = $1", [], [param(1, AUTHORS[0])]),
      query('Test', ':one',
            "SELECT #{TYPES.map(&:name).join(', ')} FROM node_postgres_types\nLIMIT 1", TYPES, [])
    ]
    opts = '{"driver":"pg","rubyVersion":"3.3","generateTypes":true,"generateGemfile":false}'
    k('GenerateRequest').new(queries: qs, plugin_options: opts, sqlc_version: 'v1.27.0')
  end
end
