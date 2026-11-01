# frozen_string_literal: true

require_relative 'proto'

# Subset of sqlc's plugin/codegen.proto needed by the generator.
# Field numbers must match https://github.com/sqlc-dev/sqlc/blob/main/protos/plugin/codegen.proto
module SqlcGenRuby
  module Plugin
    P = Proto::Message

    class File < P
      field :name, 1, :string
      field :contents, 2, :bytes
    end

    class Identifier < P
      field :catalog, 1, :string
      field :schema, 2, :string
      field :name, 3, :string
    end

    class Column < P
      field :name, 1, :string
      field :not_null, 3, :bool
      field :is_array, 4, :bool
      field :comment, 5, :string
      field :length, 6, :int32
      field :is_named_param, 7, :bool
      field :is_func_call, 8, :bool
      field :scope, 9, :string
      field :table, 10, :message, klass: Identifier
      field :table_alias, 11, :string
      field :type, 12, :message, klass: Identifier
      field :is_sqlc_slice, 13, :bool
      field :embed_table, 14, :message, klass: Identifier
      field :original_name, 15, :string
      field :unsigned, 16, :bool
      field :array_dims, 17, :int32
    end

    class Parameter < P
      field :number, 1, :int32
      field :column, 2, :message, klass: Column
    end

    class Query < P
      field :text, 1, :string
      field :name, 2, :string
      field :cmd, 3, :string
      field :columns, 4, :message, repeated: true, klass: Column
      field :params, 5, :message, repeated: true, klass: Parameter
      field :comments, 6, :string, repeated: true
      field :filename, 7, :string
      field :insert_into_table, 8, :message, klass: Identifier
    end

    class Enum < P
      field :name, 1, :string
      field :vals, 2, :string, repeated: true
      field :comment, 3, :string
    end

    class Table < P
      field :rel, 1, :message, klass: Identifier
      field :columns, 2, :message, repeated: true, klass: Column
      field :comment, 3, :string
    end

    class CompositeType < P
      field :name, 1, :string
      field :comment, 2, :string
    end

    class Schema < P
      field :comment, 1, :string
      field :name, 2, :string
      field :tables, 3, :message, repeated: true, klass: Table
      field :enums, 4, :message, repeated: true, klass: Enum
      field :composite_types, 5, :message, repeated: true, klass: CompositeType
    end

    class Catalog < P
      field :comment, 1, :string
      field :default_schema, 2, :string
      field :name, 3, :string
      field :schemas, 4, :message, repeated: true, klass: Schema
    end

    class GenerateRequest < P
      # settings(1) is skipped: the generator does not need it.
      field :catalog, 2, :message, klass: Catalog
      field :queries, 3, :message, repeated: true, klass: Query
      field :sqlc_version, 4, :string
      field :plugin_options, 5, :bytes
      field :global_options, 6, :bytes
    end

    class GenerateResponse < P
      field :files, 1, :message, repeated: true, klass: File
    end
  end
end
