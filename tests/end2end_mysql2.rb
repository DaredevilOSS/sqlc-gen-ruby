#!/usr/bin/env ruby
gem 'minitest'     # ensures using the gem, and not the built-in MT
require 'minitest/autorun'
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
    print "mysql 2 test"
    sleep 3
    skip "test this later"
  end
end