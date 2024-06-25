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
    print "pg test"
    @query_sql.list_authors
  end
end