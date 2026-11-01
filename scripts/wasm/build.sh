#!/usr/bin/env bash
# Packs the pure-Ruby plugin into a standalone WASI module (dist/plugin.wasm).
# Needs: ruby + `gem install ruby_wasm` (for `rbwasm pack`), curl, tar.
set -euo pipefail
cd "$(dirname "$0")/../.."
# shellcheck source=../tool-versions.env
source scripts/tool-versions.env
RUBY_WASM_VERSION="${RUBY_WASM_VERSION}"
FLAVOR="ruby-3.3-wasm32-unknown-wasip1-full"
# `rbwasm` comes from the ruby_wasm gem (see Gemfile, group :wasm_build)
if [ -z "${RBWASM:-}" ]; then
  if command -v rbwasm >/dev/null 2>&1; then RBWASM="rbwasm"; else RBWASM="bundle exec rbwasm"; fi
fi
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# 1. prebuilt CRuby compiled to wasm32-wasip1 (avoids `rbwasm build`, which failed on dln.c/Dl_info)
curl -fsSL -o "$WORK/ruby.tgz" \
  "https://github.com/ruby/ruby.wasm/releases/download/${RUBY_WASM_VERSION}/${FLAVOR}.tar.gz"
tar -xzf "$WORK/ruby.tgz" -C "$WORK"
SRC="$WORK/$FLAVOR/usr/local"
# the prebuilt interpreter carries ~18 MB of DWARF debug info + names: strip it
ruby scripts/wasm/strip_wasm.rb "$SRC/bin/ruby"

# 2. stage a slim filesystem to embed: core stdlib only + the plugin. sqlc gives plugins no filesystem.
STAGE="$WORK/stage"
mkdir -p "$STAGE/usr/local/lib/ruby" "$STAGE/app"
cp -r "$SRC/lib/ruby/3.3.0" "$STAGE/usr/local/lib/ruby/3.3.0"
# Not needed by the plugin (it only uses core + json). Anything required at interpreter boot (rubygems,
# monitor, ...) must stay; test/wasm_smoke_test.sh / `sqlc generate` catch an over-trimmed stdlib.
(cd "$STAGE/usr/local/lib/ruby/3.3.0" && rm -rf bundler rdoc irb reline net ruby_vm rbs typeprof debug \
  prism syntax_suggest csv csv.rb drb drb.rb cgi cgi.rb openssl openssl.rb mkmf.rb resolv.rb resolv-replace.rb \
  psych psych.rb yaml yaml.rb unicode_normalize optparse optparse.rb open3 open3.rb ripper ripper.rb \
  random rinda benchmark benchmark.rb pstore.rb tempfile.rb tmpdir.rb un.rb webrick expect.rb getoptlong.rb \
  observer.rb abbrev.rb base64.rb mutex_m.rb nkf.rb syslog.rb)
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
