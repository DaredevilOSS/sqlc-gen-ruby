SHELL 		:= /bin/bash
PWD 		:= $(shell pwd)
        
dotnet-format:
	dotnet format \
		--exclude GeneratedProtobuf \
		--exclude MySqlConnectorExample \
		--exclude NpgsqlExample

dockerfile-generate:
	./scripts/generate_dockerfile.sh Dockerfile
        
protobuf-generate:
	./scripts/generate_protobuf.sh

# tests are run against generated code - can be generated either via a "process" or "wasm" SQLC plugins
run-tests:
	./scripts/run_tests.sh

# process type plugin
dotnet-build-process: protobuf-generate dotnet-format
	dotnet build ProcessRunner -c Release

dotnet-publish-process: dotnet-build-process
	dotnet publish ProcessRunner -c release --output dist/

sqlc-generate-process: dotnet-publish-process
	sqlc -f sqlc.process.yaml generate

test-process-plugin: sqlc-generate-process dockerfile-generate run-tests

# WASM type plugin
dotnet-publish-wasm: protobuf-generate
	dotnet publish WasmRunner -c release --output dist/
	./scripts/wasm/copy_to_dist.sh

update-wasm-plugin:
	./scripts/wasm/update_sha.sh

sqlc-generate-wasm: dotnet-publish-wasm update-wasm-plugin
	SQLCCACHE=./; sqlc -f sqlc.wasm.yaml generate
	yq -i ".plugins[0].wasm.sha256 = \"SHA_TO_REPLACE\"" sqlc.wasm.yaml

test-wasm-plugin: sqlc-generate-wasm dockerfile-generate run-tests