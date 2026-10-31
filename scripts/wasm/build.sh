#!/usr/bin/env bash
# Packs the pure-Ruby plugin into a standalone WASI module (dist/plugin.wasm).
# Needs: ruby + `gem install ruby_wasm` (for `rbwasm pack`), curl, tar.
set -euo pipefail
cd "$(dirname "$0")/../.."


RUBY_WASM_VERSION="${RUBY_WASM_VERSION:-2.7.1}"
FLAVOR="ruby-3.3-wasm32-unknown-wasip1-full"
RBWASM="${RBWASM:-rbwasm}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# 1. prebuilt CRuby compiled to wasm32-wasip1 (avoids `rbwasm build`, which failed on dln.c/Dl_info)
curl -fsSL -o "$WORK/ruby.tgz" \
  "https://github.com/ruby/ruby.wasm/releases/download/${RUBY_WASM_VERSION}/${FLAVOR}.tar.gz"
tar -xzf "$WORK/ruby.tgz" -C "$WORK"
SRC="$WORK/$FLAVOR/usr/local"

# 2. stage a slim filesystem to embed: core stdlib only + the plugin. sqlc gives plugins no filesystem.
STAGE="$WORK/stage"
mkdir -p "$STAGE/usr/local/lib/ruby" "$STAGE/app"
cp -r "$SRC/lib/ruby/3.3.0" "$STAGE/usr/local/lib/ruby/3.3.0"
(cd "$STAGE/usr/local/lib/ruby/3.3.0" && rm -rf bundler rdoc irb reline net ruby_vm rbs typeprof debug)
mkdir -p "$STAGE/usr/local/lib/ruby/site_ruby" "$STAGE/usr/local/lib/ruby/vendor_ruby" "$STAGE/usr/local/lib/ruby/gems"
cp -r lib exe "$STAGE/app/"
# sqlc runs the module as `plugin.wasm /plugin.CodegenService/Generate`, so the interpreter treats that
# path as its script. Embed a file there that boots the real entry point.
mkdir -p "$STAGE/plugin.CodegenService"
echo "load '/app/exe/plugin.rb'" > "$STAGE/plugin.CodegenService/Generate"

# 3. embed it into the interpreter with wasi-vfs
mkdir -p dist
$RBWASM pack "$SRC/bin/ruby" \
  --dir "$STAGE/usr::/usr" --dir "$STAGE/app::/app" --dir "$STAGE/plugin.CodegenService::/plugin.CodegenService" \
  -o dist/plugin.wasm
du -h dist/plugin.wasm
