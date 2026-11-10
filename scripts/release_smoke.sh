#!/usr/bin/env bash

set -Eeuo pipefail

image="${1:?usage: release_smoke.sh IMAGE}"
suffix="${RANDOM}-$$"
network="keystone-smoke-${suffix}"
postgres="keystone-smoke-postgres-${suffix}"
app="keystone-smoke-app-${suffix}"
resources="keystone-smoke-resources-${suffix}"
database="keystone_phoenix_smoke"
database_url="ecto://postgres:postgres@${postgres}/${database}"

cleanup() {
  docker rm -f "${app}" "${postgres}" >/dev/null 2>&1 || true
  docker volume rm "${resources}" >/dev/null 2>&1 || true
  docker network rm "${network}" >/dev/null 2>&1 || true
}

trap cleanup EXIT

docker network create "${network}" >/dev/null
docker volume create "${resources}" >/dev/null
docker run --detach --name "${postgres}" --network "${network}" \
  --env POSTGRES_USER=postgres \
  --env POSTGRES_PASSWORD=postgres \
  --env POSTGRES_DB="${database}" \
  postgres:18 >/dev/null

for _attempt in $(seq 1 60); do
  if docker exec "${postgres}" pg_isready -U postgres -d "${database}" >/dev/null 2>&1; then
    break
  fi
  sleep 2
done

docker exec "${postgres}" pg_isready -U postgres -d "${database}" >/dev/null

private_key="$(openssl genrsa 2048 2>/dev/null)"
secret_key_base="$(openssl rand -hex 32)"
common_env=(
  --env "DATABASE_URL=${database_url}"
  --env DATABASE_SSL=false
  --env "JWT_PRIVATE_KEY=${private_key}"
  --env "SECRET_KEY_BASE=${secret_key_base}"
  --env PHX_HOST=localhost
  --env JOB_SCHEDULER_ENABLED=false
  --env FILE_BASE_DIR=/var/lib/keystone/resources
)

docker run --rm --network "${network}" "${common_env[@]}" "${image}" eval \
  "KeystonePhoenix.Release.migrate()"

docker run --rm --network "${network}" "${common_env[@]}" "${image}" eval \
  "KeystonePhoenix.Release.migrate()"

docker run --detach --name "${app}" --network "${network}" \
  --volume "${resources}:/var/lib/keystone/resources" \
  "${common_env[@]}" "${image}" >/dev/null

for _attempt in $(seq 1 60); do
  health="$(docker inspect --format '{{.State.Health.Status}}' "${app}" 2>/dev/null || true)"
  if [[ "${health}" == "healthy" ]]; then
    break
  fi
  sleep 2
done

[[ "$(docker inspect --format '{{.State.Health.Status}}' "${app}")" == "healthy" ]]
[[ "$(docker inspect --format '{{.Config.User}}' "${app}")" == "keystone" ]]
docker exec "${app}" sh -c 'test "$(id -un)" = keystone'
docker exec "${app}" sh -c 'printf smoke > /var/lib/keystone/resources/.smoke-persistence'
docker exec "${app}" curl --fail --silent http://127.0.0.1:4000/health >/dev/null
docker exec "${app}" curl --fail --silent http://127.0.0.1:4000/health/ready >/dev/null
docker exec "${app}" curl --fail --silent http://127.0.0.1:4000/login/rsa-public-key >/dev/null
docker restart "${app}" >/dev/null

for _attempt in $(seq 1 60); do
  health="$(docker inspect --format '{{.State.Health.Status}}' "${app}" 2>/dev/null || true)"
  if [[ "${health}" == "healthy" ]]; then
    break
  fi
  sleep 2
done

[[ "$(docker inspect --format '{{.State.Health.Status}}' "${app}")" == "healthy" ]]
docker exec "${app}" sh -c 'test "$(cat /var/lib/keystone/resources/.smoke-persistence)" = smoke'
docker exec "${app}" sh -c 'rm /var/lib/keystone/resources/.smoke-persistence'

echo "release smoke passed for ${image}"
