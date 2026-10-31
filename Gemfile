source 'https://rubygems.org'

# The plugin itself (lib/, exe/) is pure Ruby with no gem dependencies, so that it can run inside ruby.wasm.

# Gems used by the *generated* code (examples/ + end-to-end tests under tests/).
gem 'connection_pool'
gem 'mysql2'
gem 'pg', '1.5.2'
gem 'sqlite3'
gem 'minitest'
gem 'rake'
gem 'steep'

# Building dist/plugin.wasm (scripts/wasm/build.sh): provides `rbwasm pack`.
group :wasm_build do
  gem 'ruby_wasm', '~> 2.7'
end

# test/codec_test.rb only: independent protobuf implementation to cross-check the plugin's own codec.
group :codec_test do
  gem 'google-protobuf', '~> 4.0'
end
