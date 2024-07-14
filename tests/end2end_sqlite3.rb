#!/usr/bin/env ruby
gem 'minitest'     # ensures using the gem, and not the built-in MT
require 'minitest/autorun'
require_relative 'consts'
require_relative '../examples/sqlite3/query_sql'

class TestSqlite3 < Minitest::Test
    def setup
        db_name = "#{ENV['DB_NAME']}.db"
        db = SQLite3::Database.new db_name
        success = system("sqlite3 #{db_name} < ./examples/authors/sqlite/schema.sql")
        if success
            puts "Created schema for #{db_name}"
        end
        @query_sql = Sqlite3Codegen::QuerySql.new(db)
    end

    def test_flow
        first_inserted_id = create_first_author_and_assert
        create_second_author_and_assert
        delete_author_and_assert(first_inserted_id)
    end
    
    def create_first_author_and_assert
        create_author_args = Sqlite3Codegen::CreateAuthorArgs.new(
          name: Consts::BOJACK_AUTHOR,
          bio: Consts::BOJACK_THEME
        )
        @query_sql.create_author(create_author_args)
        inserted_id = 1
        get_author_args = Sqlite3Codegen::GetAuthorArgs.new(id: inserted_id)
        actual = @query_sql.get_author(get_author_args)
        expected = Sqlite3Codegen::GetAuthorRow.new(
          id: inserted_id, 
          name: Consts::BOJACK_AUTHOR, 
          bio: Consts::BOJACK_THEME
        )
        assert_equal(expected, actual)
        inserted_id
    end

    def create_second_author_and_assert
        create_author_args = Sqlite3Codegen::CreateAuthorArgs.new(
          name: Consts::DR_SEUSS_AUTHOR, 
          bio: Consts::DR_SEUSS_QUOTE
        )
        @query_sql.create_author(create_author_args)
        get_author_args = Sqlite3Codegen::GetAuthorArgs.new(id: 2)
        actual = @query_sql.get_author(get_author_args)
        expected = Sqlite3Codegen::GetAuthorRow.new(
          id: 2, 
          name: Consts::DR_SEUSS_AUTHOR, 
          bio: Consts::DR_SEUSS_QUOTE
        )
        assert_equal(expected, actual)
    end

    def delete_author_and_assert(id_to_delete)
        delete_author_args = Sqlite3Codegen::DeleteAuthorArgs.new(id: id_to_delete)
        @query_sql.delete_author(delete_author_args)
        actual = @query_sql.list_authors
        expected = [
          Sqlite3Codegen::ListAuthorsRow.new(
            id: 2,
            name: Consts::DR_SEUSS_AUTHOR,
            bio: Consts::DR_SEUSS_QUOTE
          )
        ]
        assert_equal(expected, actual)
    end
end