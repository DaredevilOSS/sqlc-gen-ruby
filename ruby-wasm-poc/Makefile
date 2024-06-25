SHELL 		:= /bin/bash
PWD 		:= $(shell pwd)
RUBY_WASM 	:= ${HOME}/bin/ruby-wasm

protobuf-generate:
	./scripts/generate_protobuf.sh

tebako-build:
	tebako press \
      --root='.' \
      --entry=bin/plugin.rb \
      --output=dist/plugin.tebako \
      --Ruby=3.2.3 \
      --log-level=debug # TODO if removed - fails on segmentation fault

wasm-build:
	rbwasm build --remake --reconfigure --ruby-version 3.2 -o dist/plugin.wasm
	echo "WASM filesize:" && du -sh dist/plugin.wasm

sync-wasm-sha: protobuf-generate wasm-build
	./scripts/sync_wasm_sha.sh

sqlc-generate-process: protobuf-generate tebako-build
	sqlc -f sqlc.process.yaml generate

sqlc-generate-wasm: sync-wasm-sha
	SQLCCACHE=./; sqlc -f sqlc.wasm.yaml generate
