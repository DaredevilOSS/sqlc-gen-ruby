#!/usr/bin/env bash
# Packs the pure-Ruby plugin into a standalone WASI module (dist/plugin.wasm).
#
# STATUS: UNVERIFIED. Written without network access to the ruby.wasm release
# assets, so this has not been run end to end. See README.md ("Open problem: argv").
set -euo pipefail
cd "$(dirname "$0")/.."

RUBY_WASM_VERSION="${RUBY_WASM_VERSION:-2.7.1}"
RUBY_WASM_FLAVOR="ruby-3.3-wasm32-unknown-wasip1-full"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# 1. prebuilt CRuby compiled to wasm32-wasip1 (no need for `rbwasm build`, which is what broke before)
curl -fsSL -o "$WORK/ruby.tgz" \
  "https://github.com/ruby/ruby.wasm/releases/download/${RUBY_WASM_VERSION}/${RUBY_WASM_FLAVOR}.tar.gz"
tar -xzf "$WORK/ruby.tgz" -C "$WORK"

# 2. embed the stdlib + our code in the wasm file itself via wasi-vfs (sqlc gives plugins no filesystem)
mkdir -p dist
bundle exec rbwasm pack "$WORK/${RUBY_WASM_FLAVOR}/usr/local/bin/ruby" \
  --dir "$WORK/${RUBY_WASM_FLAVOR}/usr/local/lib/ruby::/usr/local/lib/ruby" \
  --dir ./lib::/app/lib \
  --dir ./exe::/app/exe \
  -o dist/plugin.wasm

du -h dist/plugin.wasm
