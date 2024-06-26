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
        create_first_author_and_assert
        create_second_author_and_assert
    end

    def create_first_author_and_assert
        create_author_args = PgCodegen::CreateAuthorArgs.new(
          name: Consts::BOJACK_AUTHOR,
          bio: Consts::BOJACK_THEME
        )
        @query_sql.create_author(create_author_args)
        get_author_args = PgCodegen::GetAuthorArgs.new(id: 1)
        actual = @query_sql.get_author(get_author_args)
        expected = PgCodegen::GetAuthorRow.new(
          id: "1", # TODO why converted to string is necessary?
          name: Consts::BOJACK_AUTHOR,
          bio: Consts::BOJACK_THEME
        )
        assert_equal(expected, actual)
    end

    def create_second_author_and_assert
        # create_author_args = PgCodegen::CreateAuthorArgs.new(
        #   name: Consts::DR_SEUSS_AUTHOR,
        #   bio: Consts::DR_SEUSS_QUOTE
        # )
        # @query_sql.create_author(create_author_args)
        # get_author_args = PgCodegen::GetAuthorArgs.new(id: 1)
        # actual = @query_sql.get_author(get_author_args)
        # expected = PgCodegen::GetAuthorRow.new(
        #   id: 2,
        #   name: Consts::DR_SEUSS_AUTHOR,
        #   bio: Consts::DR_SEUSS_QUOTE
        # )
        # assert_equal(expected, actual)
    end
end