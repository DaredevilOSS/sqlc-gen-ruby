#!/usr/bin/env ruby
gem 'minitest'     # ensures using the gem, and not the built-in MT
require 'minitest/autorun'
require_relative 'consts'
require_relative '../examples/mysql2/query_sql'

class TestMysql2 < Minitest::Test
    def setup
        mysql2_params = {
            'dbname' =>  ENV['DB_NAME'],
            'host' => ENV['MYSQL_HOST'], 
            'username' => ENV['DB_USER'] 
        }
        @query_sql = Mysql2Codegen::QuerySql.new({ }, mysql2_params)
    end

    def test_flow
        create_first_author_and_assert
        create_second_author_and_assert
    end
    
    def create_first_author_and_assert
        create_author_return_id_args = Mysql2Codegen::CreateAuthorReturnIdArgs.new(
          name: Consts::BOJACK_AUTHOR,
          bio: Consts::BOJACK_THEME
        )
        inserted_id = @query_sql.create_author_return_id(create_author_return_id_args)
        get_author_args = Mysql2Codegen::GetAuthorArgs.new(id: inserted_id)
        actual = @query_sql.get_author(get_author_args)
        expected = Mysql2Codegen::GetAuthorRow.new(
          id: inserted_id, 
          name: Consts::BOJACK_AUTHOR, 
          bio: Consts::BOJACK_THEME
        )
        assert_equal(expected, actual)
    end

    def create_second_author_and_assert
        # create_author_args = Mysql2Codegen::CreateAuthorArgs.new(
        #   name: Consts::DR_SEUSS_AUTHOR, 
        #   bio: Consts::DR_SEUSS_QUOTE
        # )
        # @query_sql.create_author(create_author_args)
        # get_author_args = Mysql2Codegen::GetAuthorArgs.new(id: 1)
        # actual = @query_sql.get_author(get_author_args)
        # expected = Mysql2Codegen::GetAuthorRow.new(
        #   id: 2, 
        #   name: Consts::DR_SEUSS_AUTHOR, 
        #   bio: Consts::DR_SEUSS_QUOTE
        # )
        # assert_equal(expected, actual)
    end
end