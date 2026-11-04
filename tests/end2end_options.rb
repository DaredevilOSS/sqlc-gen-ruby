#!/usr/bin/env ruby
# frozen_string_literal: true

gem 'minitest'
require 'minitest/autorun'
require 'bundler'
require 'fileutils'
require 'connection_pool'
require 'open3'
require 'pg'
require 'rbconfig'
require 'sqlite3'
require 'yaml'

class TestOptions < Minitest::Test
  ROOT = File.expand_path('..', __dir__)
  OPTIONS_DIR = File.join(ROOT, 'tests/options')
  OUTPUT_DIR = File.join(OPTIONS_DIR, '.generated')

  def test_generator_options_preserve_runtime_values_and_generate_expected_layouts
    FileUtils.rm_rf(OUTPUT_DIR)
    config_path = File.join(OPTIONS_DIR, ".sqlc-#{Process.pid}.yaml")
    begin
      config = YAML.safe_load_file(File.join(OPTIONS_DIR, 'sqlc.yaml'))
      config.fetch('options').fetch('ruby')['rubyVersion'] = RUBY_VERSION.split('.')[0, 2].join('.')
      # Windows cannot execute exe/plugin.rb directly; cmd.exe needs backslashes (it reads `/plugin.cmd` as a switch)
      config.fetch('plugins').first.fetch('process')['cmd'] = 'exe\\plugin.cmd' if Gem.win_platform?
      File.write(config_path, config.to_yaml)
      assert system('sqlc', 'generate', '-f', config_path, chdir: ROOT)
      sqlite_dir = File.join(OUTPUT_DIR, 'sqlite3')
      pg_dir = File.join(OUTPUT_DIR, 'pg')
      assert_equal %w[admin_users_sql.rb admin_users_sql.rbs first_sql.rb first_sql.rbs second_sql.rb second_sql.rbs models.rb
                     models.rbs connection.rb connection.rbs Gemfile].sort,
                   Dir.children(sqlite_dir).sort
      refute Dir.children(pg_dir).any? { |file| file.end_with?('.rbs') }
      assert File.file?(File.join(pg_dir, 'Gemfile'))

      models = File.read(File.join(sqlite_dir, 'models.rb'))
      %w[Author Articles Authors SQLiteItems].each { |name| assert_model_defined(models, name) }
      pg_models = File.read(File.join(pg_dir, 'models.rb'))
      %w[GlobalAuthors PgItems].each { |name| assert_model_defined(pg_models, name) }

      rbs = File.read(File.join(sqlite_dir, 'first_sql.rbs'))
      assert_match(/memo: Pathname\b/, rbs)
      assert_match(/tag: Symbol\b/, rbs)
      assert_match(/extra: Date\b/, rbs)
      assert_match(/id: String\b/, rbs)
      assert_match(/class GetBothModelsRow\b/, rbs)
      assert File.file?(File.join(sqlite_dir, 'second_sql.rbs'))
      admin = File.read(File.join(sqlite_dir, 'admin_users_sql.rb'))
      assert_match(/^ *class AdminUsersSql$/, admin)

      assert_sqlite_runtime(sqlite_dir)
      assert_pg_runtime(pg_dir)
    ensure
      FileUtils.rm_rf(OUTPUT_DIR)
      FileUtils.rm_f(config_path)
    end
  end

  private

  def assert_model_defined(source, name)
    assert_match(/(?:^|\n)\s*(?:#{Regexp.escape(name)}\s*=\s*(?:::)?Struct\.new|class\s+#{Regexp.escape(name)}\s*<\s*(?:::)?Data\.define)/,
                 source)
  end

  def assert_sqlite_runtime(generated_dir)
    gemfile = File.join(generated_dir, 'Gemfile')
    bundle_env = Bundler.unbundled_env.merge(
      'BUNDLE_BIN_PATH' => nil, 'BUNDLE_PATH' => ENV['BUNDLE_PATH'], 'RUBYOPT' => nil,
      'BUNDLE_GEMFILE' => gemfile, 'OPTIONS_SQLITE_DIR' => generated_dir,
      'OPTIONS_SCHEMA' => File.join(OPTIONS_DIR, 'sqlite_schema.sql')
    )
    stdout, stderr, status = Open3.capture3(bundle_env, 'bundle', 'install')
    assert status.success?, "generated-Gemfile bundle install failed:\n#{stdout}\n#{stderr}"
    stdout, stderr, status = Open3.capture3(
      bundle_env,
      'bundle', 'exec', RbConfig.ruby, '-e', <<~'RUBY'
        require File.join(ENV.fetch('OPTIONS_SQLITE_DIR'), 'first_sql')
        require File.join(ENV.fetch('OPTIONS_SQLITE_DIR'), 'second_sql')
        require File.join(ENV.fetch('OPTIONS_SQLITE_DIR'), 'admin_users_sql')
        db = SQLite3::Database.new(':memory:')
        db.execute_batch(File.read(ENV.fetch('OPTIONS_SCHEMA')))
        db.execute("INSERT INTO option_items VALUES (1, 'note', 'tag', 'extra')")
        db.execute("INSERT INTO author VALUES (1, 'singular')")
        db.execute("INSERT INTO authors VALUES (1, 'plural')")
        db.execute("INSERT INTO articles VALUES (1, 'article')")
        options = Options::SqliteDb
        row = options::FirstSql.new(db).get_option_author(id: 1)
        raise 'override changed the runtime value' unless [row.id, row.memo, row.tag, row.extra] == [1, 'note', 'tag', 'extra']
        raise 'models were not shared by query files' unless options::SecondSql.new(db).get_option_extra(id: 1).extra == 'extra'
        joined = options::FirstSql.new(db).get_both_models(id: 1)
        raise 'embedded models were not renamed as expected' unless [joined.author.name, joined.author2.name] == %w[singular plural]
        raise 'exactTableNames did not preserve the plural table model' unless options::FirstSql.new(db).list_option_articles.first.title == 'article'
        raise 'admin_users.sql did not become AdminUsersSql' unless options::AdminUsersSql.new(db).count_option_articles.total == 1
      RUBY
    )
    assert status.success?, "generated-Gemfile SQLite run failed:\n#{stdout}\n#{stderr}"
  end

  def assert_pg_runtime(generated_dir)
    params = {
      dbname: ENV.fetch('DB_NAME'), host: ENV.fetch('POSTGRES_HOST'),
      user: ENV.fetch('DB_USER'), password: ENV.fetch('DB_PASS'), port: ENV['POSTGRES_PORT']
    }.compact
    conn = PG.connect(**params)
    conn.exec(File.read(File.join(OPTIONS_DIR, 'pg_schema.sql')))
    conn.exec("INSERT INTO options_audit.option_items VALUES (1, 'note', 'tag', 'extra') ON CONFLICT (id) DO UPDATE SET note = EXCLUDED.note")
    queries_path = File.join(generated_dir, 'first_sql.rb')
    require queries_path
    pool = ConnectionPool.new(size: 1) { PG.connect(**params) }
    row = Options::PgDb::FirstSql.new(pool).get_pg_option_author(id: 1)
    assert_equal [1, 'note', 'tag', 'extra'], [row.id, row.memo, row.tag, row.extra]
    require File.join(OUTPUT_DIR, 'pg_first/first_sql.rb')
    require File.join(OUTPUT_DIR, 'pg_second/first_sql.rb')
    first = Options::PgFirst::FirstSql.new(pool)
    second = Options::PgSecond::FirstSql.new(pool)
    2.times do
      assert_equal 1, first.get_pg_option_author(id: 1).id
      assert_equal 'second module', second.get_pg_option_author(id: 1).label
    end
    long = 'Options::PgLongModuleNameThatPushesStatementNamesPastTheLimit'
    [%w[pg_v2 pg_nested_v2 Options::PgV2 Options::Pg::V2], ['pg_long_a', 'pg_long_b', "#{long}A", "#{long}B"]]
      .each do |first_dir, second_dir, first_module, second_module|
        require File.join(OUTPUT_DIR, first_dir, 'first_sql.rb')
        require File.join(OUTPUT_DIR, second_dir, 'first_sql.rb')
        first = Object.const_get("#{first_module}::FirstSql").new(pool)
        second = Object.const_get("#{second_module}::FirstSql").new(pool)
        2.times do
          assert_equal 1, first.get_pg_option_author(id: 1).id, first_module
          assert_equal 'second module', second.get_pg_option_author(id: 1).label, second_module
        end
      end
  ensure
    pool&.shutdown(&:close)
    conn&.exec('DROP SCHEMA IF EXISTS options_audit CASCADE')
    conn&.close
  end
end
