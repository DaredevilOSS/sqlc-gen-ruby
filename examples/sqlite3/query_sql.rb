# auto-generated by sqlc - do not edit
require 'connection_pool'
require 'sqlite3'

module Sqlite3Codegen
	GetAuthorSql = %q(SELECT id, name, bio FROM authors
	WHERE id = ? LIMIT 1)
	
	class GetAuthorRow < Data.define(:id, :name, :bio)
	end
	
	class GetAuthorArgs < Data.define(:id)
	end
	
	ListAuthorsSql = %q(SELECT id, name, bio FROM authors
	ORDER BY name)
	
	class ListAuthorsRow < Data.define(:id, :name, :bio)
	end
	
	CreateAuthorSql = %q(INSERT INTO authors (
	  name, bio
	) VALUES (
	  ?, ?
	))
	
	class CreateAuthorArgs < Data.define(:name, :bio)
	end
	
	DeleteAuthorSql = %q(DELETE FROM authors
	WHERE id = ?)
	
	class DeleteAuthorArgs < Data.define(:id)
	end
	
	class QuerySql
		def initialize(db)
			@db = db
		end
		
		def get_author(get_author_args)
			client = @db
			query_params = [get_author_args.id]
			stmt = client.prepare(GetAuthorSql)
			result = stmt.execute(*query_params)
			row = result.first
			return nil if row.nil?
			entity = GetAuthorRow.new(row[0], row[1], row[2])
			return entity
		end
		
		def list_authors
			client = @db
			stmt = client.prepare(ListAuthorsSql)
			result = stmt.execute
			entities = []
			result.each do |row|
				entities << ListAuthorsRow.new(row[0], row[1], row[2])
			end
			return entities
		end
		
		def create_author(create_author_args)
			client = @db
			query_params = [create_author_args.name, create_author_args.bio]
			stmt = client.prepare(CreateAuthorSql)
			stmt.execute(*query_params)
		end
		
		def delete_author(delete_author_args)
			client = @db
			query_params = [delete_author_args.id]
			stmt = client.prepare(DeleteAuthorSql)
			stmt.execute(*query_params)
		end
	end
end