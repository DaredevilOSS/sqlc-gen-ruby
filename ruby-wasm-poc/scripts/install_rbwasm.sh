#!/usr/bin/env bash

set -ex

# uninstall
gem uninstall ruby_wasm --all --executables
asdf uninstall ruby 3.2.2 || echo "ruby not installed"

# install
gem install ruby_wasm
brew install libyaml
gem install psych -- --with-libyaml-dir="$(brew --prefix libyaml)"
RUBY_CONFIGURE_OPTS="--with-libyaml-dir=$(brew --prefix libyaml)"
export RUBY_CONFIGURE_OPTS
asdf install ruby 3.2.2 && asdf global ruby 3.2.2

cd /tmp && curl -LO --silent \
  https://github.com/ruby/ruby.wasm/releases/download/2.6.1/ruby-3.2-wasm32-unknown-wasip1-full.tar.gz
tar xvf ruby-3.2-wasm32-unknown-wasip1-full.tar.gz
mv /tmp/ruby-3.2-wasm32-unknown-wasip1-full/usr/local/bin/ruby ~/bin/ruby.wasm