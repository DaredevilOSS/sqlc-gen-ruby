#!/usr/bin/env ruby
gem 'minitest'     # ensures using the gem, and not the built-in MT
require 'minitest/autorun'
require_relative '../examples/pg/query_sql'

class TestPg < Minitest::Test
    def setup
        pg_params = { 
            'dbname' =>  ENV['DB_NAME'],
            'host' => ENV['POSTGRES_HOST'],
            'user' => ENV['DB_USER'],
            'password' => ENV['DB_PASS']
        }
        @query_sql = PgCodegen::QuerySql.new({ }, pg_params)
    end

    def test_flow
        first_inserted_id = create_first_author_and_assert
        create_second_author_and_assert
        delete_author_and_assert(first_inserted_id)
    end

    def create_first_author_and_assert
        create_author_args = PgCodegen::CreateAuthorArgs.new(
          name: Consts::BOJACK_AUTHOR,
          bio: Consts::BOJACK_THEME
        )
        @query_sql.create_author(create_author_args)
        inserted_id = 1
        get_author_args = PgCodegen::GetAuthorArgs.new(id: inserted_id)
        actual = @query_sql.get_author(get_author_args)
        expected = PgCodegen::GetAuthorRow.new(
          id: 1,
          name: Consts::BOJACK_AUTHOR,
          bio: Consts::BOJACK_THEME
        )
        assert_equal(expected, actual)
        inserted_id
    end

    def create_second_author_and_assert
        create_author_args = PgCodegen::CreateAuthorArgs.new(
          name: Consts::DR_SEUSS_AUTHOR,
          bio: Consts::DR_SEUSS_QUOTE
        )
        @query_sql.create_author(create_author_args)
        get_author_args = PgCodegen::GetAuthorArgs.new(id: 2)
        actual = @query_sql.get_author(get_author_args)
        expected = PgCodegen::GetAuthorRow.new(
          id: 2,
          name: Consts::DR_SEUSS_AUTHOR,
          bio: Consts::DR_SEUSS_QUOTE
        )
        assert_equal(expected, actual)
    end

    def delete_author_and_assert(id_to_delete)
        delete_author_args = PgCodegen::DeleteAuthorArgs.new(id: id_to_delete)
        @query_sql.delete_author(delete_author_args)
        actual = @query_sql.list_authors
        expected = [
          PgCodegen::ListAuthorsRow.new(
            id: 2,
            name: Consts::DR_SEUSS_AUTHOR,
            bio: Consts::DR_SEUSS_QUOTE
          )
        ]
        assert_equal(expected, actual)
    end
end