#!/usr/bin/env bash

set -Eeuo pipefail

image="${1:?usage: release_smoke.sh IMAGE}"
suffix="${RANDOM}-$$"
network="keystone-smoke-${suffix}"
postgres="keystone-smoke-postgres-${suffix}"
app="keystone-smoke-app-${suffix}"
resources="keystone-smoke-resources-${suffix}"
dump_file="$(mktemp)"
database="keystone_phoenix_smoke"
database_url="ecto://postgres:postgres@${postgres}/${database}"

cleanup() {
  docker rm -f "${app}" "${postgres}" >/dev/null 2>&1 || true
  docker volume rm "${resources}" >/dev/null 2>&1 || true
  docker network rm "${network}" >/dev/null 2>&1 || true
  rm -f "${dump_file}"
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
  --env DATABASE_SSL_ALLOW_INSECURE=true
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

docker exec "${postgres}" pg_dump -U postgres --format=custom "${database}" >"${dump_file}"
restore_database="keystone_phoenix_smoke_restore"
docker exec "${postgres}" createdb -U postgres "${restore_database}"
docker exec -i "${postgres}" pg_restore --clean --if-exists --dbname="${restore_database}" <"${dump_file}"
restored_migrations="$(docker exec "${postgres}" psql -U postgres -d "${restore_database}" -Atc \
  'SELECT count(*) FROM schema_migrations')"
[[ "${restored_migrations}" =~ ^[1-9][0-9]*$ ]]

token="$({
  docker run --rm --network "${network}" "${common_env[@]}" "${image}" eval \
    'user = %KeystonePhoenix.User.SysUser{} |> KeystonePhoenix.User.SysUser.create_changeset(%{username: "smoke_admin_#{System.unique_integer([:positive])}", password: "Strong!123"}) |> Ecto.Changeset.put_change(:is_admin, true) |> KeystonePhoenix.Repo.insert!(); {:ok, tokens} = KeystonePhoenix.Auth.login_plaintext(user.username, "Strong!123"); IO.puts(tokens.token)'
} | tail -n 1)"
[[ "${token}" =~ ^ey[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$ ]]

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
docker exec "${app}" sh -c 'printf smoke > /tmp/smoke.txt && printf smoke > /var/lib/keystone/resources/.smoke-persistence'
unauth_upload_status="$(docker exec "${app}" curl --silent --output /dev/null --write-out '%{http_code}' \
  --form file=@/tmp/smoke.txt http://127.0.0.1:4000/file/upload)"
[[ "${unauth_upload_status}" == "401" ]]

upload_json="$(docker exec "${app}" curl --fail --silent \
  --header "Authorization: Bearer ${token}" \
  --form file=@/tmp/smoke.txt http://127.0.0.1:4000/file/upload)"
upload_url="$(python -c 'import json, sys; print(json.load(sys.stdin)["data"]["url"])' <<<"${upload_json}")"
[[ "${upload_url}" == /profile/upload/* ]]

unauth_resource_status="$(docker exec "${app}" curl --silent --output /dev/null --write-out '%{http_code}' \
  http://127.0.0.1:4000"${upload_url}")"
[[ "${unauth_resource_status}" == "401" ]]
downloaded="$(docker exec "${app}" curl --fail --silent \
  --header "Authorization: Bearer ${token}" \
  http://127.0.0.1:4000"${upload_url}")"
[[ "${downloaded}" == "smoke" ]]

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
downloaded_after_restart="$(docker exec "${app}" curl --fail --silent \
  --header "Authorization: Bearer ${token}" \
  http://127.0.0.1:4000"${upload_url}")"
[[ "${downloaded_after_restart}" == "smoke" ]]
docker exec "${app}" sh -c 'rm /tmp/smoke.txt /var/lib/keystone/resources/.smoke-persistence'

echo "release smoke passed for ${image}"
