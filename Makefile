SHELL 		:= /bin/bash
PWD 		:= $(shell pwd)

 # TODO automate these 2
RUNTIME 	:= osx-arm64
RUNTIME_DIR := SqlcGenCsharp/bin/Release/net8.0/${RUNTIME}

PATH  		:= ${PATH}:${PWD}/${RUNTIME_DIR}

buf-gen:
	buf generate --template buf.gen.yaml buf.build/sqlc/sqlc --path plugin/

dotnet-build:
	dotnet build

dotnet-publish: buf-gen dotnet-build
	dotnet publish SqlcGenCsharp --runtime ${RUNTIME} -c release --output dist/
	# cp ${RUNTIME_DIR}/SqlcGenCsharp.wasm dist/plugin.wasm

sqlc-generate: dotnet-publish
	sqlc -f sqlc.dev.yaml generate

test-setup: test-teardown
	docker-compose up --wait -d
	docker exec -it mysqldb /bin/bash -c "mysql -h localhost --database tests < /var/db/schema.sql"

dotnet-test-internal:
	dotnet test

dotnet-test: test-setup dotnet-test-internal test-teardown

test-teardown:
	docker-compose down
	