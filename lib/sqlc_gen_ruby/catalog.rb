# frozen_string_literal: true

require_relative 'code'

module SqlcGenRuby
  # Read-only view of the GenerateRequest catalog: tables (-> model classes, sqlc.embed) and enums.
  class Catalog
    INTERNAL_SCHEMAS = %w[pg_catalog information_schema pg_temp].freeze

    Table = Struct.new(:schema, :name, :columns, :model_name)

    attr_reader :tables, :enums

    def initialize(proto_catalog)
      @default_schema = proto_catalog&.default_schema.to_s
      schemas = (proto_catalog&.schemas || []).reject { |s| INTERNAL_SCHEMAS.include?(s.name) }
      @tables = schemas.flat_map do |schema|
        schema.tables.map do |t|
          Table.new(schema.name, t.rel.name, t.columns, nil)
        end
      end
      assign_model_names
      # qualified enum name => values; default-schema enums are reachable both bare and qualified
      @enums = {}
      @composites = schemas.flat_map do |schema|
        schema.composite_types.flat_map do |c|
          default_schema?(schema.name) ? [c.name, "#{schema.name}.#{c.name}"] : ["#{schema.name}.#{c.name}"]
        end
      end
      schemas.each do |schema|
        schema.enums.each do |e|
          @enums["#{schema.name}.#{e.name}"] = e.vals.to_a
          @enums[e.name] = e.vals.to_a if default_schema?(schema.name)
        end
      end
    end

    def enum?(type) = @enums.key?(qualified_name(type))

    # CREATE TYPE ... AS (...): the pg gem returns the record text, e.g. "(1,abc)"
    def composite?(type) = @composites.include?(qualified_name(type))

    def enum_values(type) = @enums[qualified_name(type)]

    # Enums with their Ruby module names, one entry per distinct enum.
    def enum_modules
      @enums.reject { |name, _| name.include?('.') && default_schema?(name.split('.').first) }
            .map { |name, vals| [Code.camelize(name), vals] }
    end

    # embed_table: Identifier(schema, name) as sqlc sends it for sqlc.embed
    def table_for(identifier)
      @tables.find do |t|
        t.name == identifier.name && (identifier.schema.empty? || t.schema == identifier.schema ||
                                      (t.schema == @default_schema && identifier.schema == @default_schema))
      end
    end

    private

    def default_schema?(name) = name.empty? || name == @default_schema

    # Identifier / column type -> "schema.name" for non default schemas
    def qualified_name(type)
      name = type.name.to_s.sub(/\Apg_catalog\./, '')
      return name if name.include?('.') || type.schema.to_s.empty? || type.schema == 'pg_catalog'

      "#{type.schema}.#{name}"
    end

    # authors => Author; when two tables would share a model (author and authors) the plural one keeps its plural name.
    def assign_model_names
      @tables.each { |t| t.model_name = model_name(t, Code.singularize(t.name)) }
      @tables.group_by(&:model_name).each_value do |same|
        same.each { |t| t.model_name = model_name(t, t.name) } if same.size > 1
      end
      @tables.group_by(&:model_name).each do |name, same|
        next if same.size == 1

        tables = same.map { |t| "#{t.schema}.#{t.name}" }.join(', ')
        raise ArgumentError, "tables #{tables} would all generate the model class #{name}"
      end
    end

    def model_name(table, base)
      name = Code.camelize(base)
      default_schema?(table.schema) ? name : Code.camelize(table.schema) + name
    end
  end
end
