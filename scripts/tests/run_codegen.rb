#!/usr/bin/env ruby
# frozen_string_literal: true

# Runs `sqlc generate` with a sqlc config for different plugin options and checks what comes out, without touching
# the checked-in examples (they are verified separately with `sqlc diff`).
#
#   scripts/tests/run_codegen.rb <sqlc config> <rubyVersion> <generateTypes> <generateGemfile>
#
# Checks, for every `sql:` block of the config:
#   * every generated .rb file is valid Ruby (for the Ruby running this script) and models/connection files load
#   * .rbs files exist iff generateTypes, a Gemfile exists iff generateGemfile
require 'fileutils'
require 'yaml'

config_path, ruby_version, generate_types, generate_gemfile = ARGV
abort "usage: #{$PROGRAM_NAME} <sqlc config> <rubyVersion> <generateTypes> <generateGemfile>" unless generate_gemfile

types = generate_types == 'true'
gemfile = generate_gemfile == 'true'
config = YAML.safe_load_file(config_path)

# sqlc resolves `out:` relative to the config file, so the scratch directory lives next to it (gitignored)
config_dir = File.dirname(config_path)
scratch = ".codegen-test-out-#{Process.pid}"
out_root = File.join(config_dir, scratch)

begin
  config['sql'].each do |sql|
    codegen = sql['codegen'].first
    options = codegen['options']
    codegen['out'] = File.join(scratch, options['driver'])
    options.merge!('rubyVersion' => ruby_version, 'generateTypes' => types, 'generateGemfile' => gemfile)
    puts "#{options['driver']}: #{options}"
  end

  # sqlc resolves paths relative to the config file: write the temporary config next to the original
  tmp_config = File.join(config_dir, ".codegen-test.#{Process.pid}.yaml")
  begin
    File.write(tmp_config, config.to_yaml)
    system('sqlc', '-f', tmp_config, 'generate') or abort('sqlc generate failed')
  ensure
    FileUtils.rm_f(tmp_config)
  end

  failures = []
  config['sql'].each do |sql|
    driver = sql['codegen'].first['options']['driver']
    dir = File.join(out_root, driver)
    files = Dir.children(dir).sort
    puts "#{driver}: #{files.join(', ')}"

    failures << "#{driver}: no query_sql.rb" unless files.include?('query_sql.rb')
    failures << "#{driver}: .rbs files #{types ? 'missing' : 'generated although generateTypes is false'}" if files.grep(/\.rbs\z/).empty? == types
    failures << "#{driver}: Gemfile #{gemfile ? 'missing' : 'generated although generateGemfile is false'}" if files.include?('Gemfile') != gemfile

    files.grep(/\.rb\z/).each do |file|
      path = File.join(dir, file)
      failures << "#{driver}/#{file} is not valid Ruby" unless system(RbConfig.ruby, '-c', path, out: File::NULL)
    end
    # models.rb / connection.rb have no dependencies: they must actually load (Data / Struct classes are valid)
    %w[connection.rb models.rb].each do |file|
      path = File.join(dir, file)
      next unless File.exist?(path)

      failures << "#{driver}/#{file} does not load" unless system(RbConfig.ruby, '-e', "require 'set'; load ARGV[0]", path)
    end
  end

  abort(failures.map { |f| "FAIL #{f}" }.join("\n")) unless failures.empty?
  puts 'codegen checks passed'
ensure
  FileUtils.rm_rf(out_root)
end
