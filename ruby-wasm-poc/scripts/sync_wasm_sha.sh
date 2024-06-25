#!/usr/bin/env bash

PLUGIN_SHA=$(shasum -a 256 dist/plugin.wasm | awk '{ print $1 }')
yq -i ".plugins[0].wasm.sha256 = \"${PLUGIN_SHA}\"" sqlc.wasm.yaml