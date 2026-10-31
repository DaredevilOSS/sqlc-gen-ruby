#!/usr/bin/env bash
# Local end-to-end run: starts MySQL + PostgreSQL with docker-compose and runs tests/end2end_*.rb in a container.
# (CI runs the same tests against service containers, see .github/workflows/tests.yml.)
set -ex

destroy() { docker-compose down --volumes; }
trap destroy EXIT

source .env
docker-compose up --detach --build --force-recreate --remove-orphans
tests_container_id=$(docker ps -aqf "name=${TESTS_CONTAINER_NAME}")
tests_exit_code=$(docker wait "${TESTS_CONTAINER_NAME}")

# by container_id since the container is dead
docker logs --timestamps "${tests_container_id}" > tests.log && cat tests.log

exit "${tests_exit_code}"
