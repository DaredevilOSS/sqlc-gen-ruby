#!/usr/bin/env bash
# Writes the sha256 of dist/plugin.wasm into the sqlc config (plugins[].wasm.sha256) - idempotent.
set -euo pipefail

filename=${1:?usage: update_sha.sh <sqlc config>}
if command -v sha256sum >/dev/null 2>&1; then sha=(sha256sum); else sha=(shasum -a 256); fi # Git Bash / macOS
plugin_sha=$("${sha[@]}" dist/plugin.wasm | awk '{ print $1 }')
sed -i.bak -E "s/^([[:space:]]*sha256:[[:space:]]*).*/\1${plugin_sha}/" "${filename}" && rm -f "${filename}.bak"
grep -q "${plugin_sha}" "${filename}" || { echo "no sha256: line in ${filename}" >&2; exit 1; }
