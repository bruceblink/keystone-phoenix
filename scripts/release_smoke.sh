#!/usr/bin/env bash

set -Eeuo pipefail

image="${1:?usage: release_smoke.sh IMAGE}"
suffix="${RANDOM}-$$"
network="keystone-smoke-${suffix}"
postgres="keystone-smoke-postgres-${suffix}"
app="keystone-smoke-app-${suffix}"
resources="keystone-smoke-resources-${suffix}"
dump_file="$(mktemp)"
public_key_der_file="$(mktemp)"
public_key_pem_file="$(mktemp)"
encrypted_password_file="$(mktemp)"
database="keystone_phoenix_smoke"
database_url="ecto://postgres:postgres@${postgres}/${database}"
postgres_image="postgres:18@sha256:e3d24f6906d0760bf4da0dae872415391ededefad23fd471c47dc53b0ddf3c42"
smoke_username="smoke_admin_${RANDOM}_$$"
smoke_password="Strong!123"

# 解析成功响应中的访问令牌和刷新令牌，避免在烟测输出中打印令牌内容。
extract_token_pair() {
  python -c '
import json
import sys

try:
    response = json.load(sys.stdin)
    data = response["data"]
    access_token = data["token"]
    refresh_token = data["refreshToken"]
except (KeyError, TypeError, ValueError):
    raise SystemExit(1)

if response.get("success") is not True or not isinstance(access_token, str) or not isinstance(refresh_token, str):
    raise SystemExit(1)

print(f"{access_token}\t{refresh_token}")
'
}

cleanup() {
  docker rm -f "${app}" "${postgres}" >/dev/null 2>&1 || true
  docker volume rm "${resources}" >/dev/null 2>&1 || true
  docker network rm "${network}" >/dev/null 2>&1 || true
  rm -f "${dump_file}" "${public_key_der_file}" "${public_key_pem_file}" "${encrypted_password_file}"
}

trap cleanup EXIT

docker network create "${network}" >/dev/null
docker volume create "${resources}" >/dev/null
docker run --detach --name "${postgres}" --network "${network}" \
  --env POSTGRES_USER=postgres \
  --env POSTGRES_PASSWORD=postgres \
  --env POSTGRES_DB="${database}" \
  "${postgres_image}" >/dev/null

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
docker exec -i "${postgres}" pg_restore -U postgres --clean --if-exists --dbname="${restore_database}" <"${dump_file}"
restored_migrations="$(docker exec "${postgres}" psql -U postgres -d "${restore_database}" -Atc \
  'SELECT count(*) FROM schema_migrations')"
[[ "${restored_migrations}" =~ ^[1-9][0-9]*$ ]]

# 仅在烟测数据库中创建管理员测试用户，登录流程仍通过 HTTP 执行。
docker run --rm --network "${network}" "${common_env[@]}" \
  --env "SMOKE_USERNAME=${smoke_username}" \
  --env "SMOKE_PASSWORD=${smoke_password}" \
  "${image}" eval \
  'Application.ensure_all_started(:keystone_phoenix); admin_role = KeystonePhoenix.Repo.get_by!(KeystonePhoenix.Role.SysRole, role_key: "admin", deleted: false); %KeystonePhoenix.User.SysUser{} |> KeystonePhoenix.User.SysUser.create_changeset(%{username: System.fetch_env!("SMOKE_USERNAME"), password: System.fetch_env!("SMOKE_PASSWORD"), role_id: admin_role.role_id}) |> KeystonePhoenix.Repo.insert!()' >/dev/null

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

# 通过真实 HTTP 请求验证 RSA 登录、刷新令牌轮换和受保护接口访问。
public_key_json="$(docker exec "${app}" curl --fail --silent \
  http://127.0.0.1:4000/api/v1/auth/rsa-public-key)"
printf '%s' "${public_key_json}" | python -c \
  'import base64, json, sys; sys.stdout.buffer.write(base64.b64decode(json.load(sys.stdin)["data"]["publicKey"]))' \
  >"${public_key_der_file}"
openssl pkey -pubin -inform DER -in "${public_key_der_file}" -out "${public_key_pem_file}" \
  >/dev/null 2>&1
printf '%s' "${smoke_password}" | openssl pkeyutl -encrypt -pubin \
  -inkey "${public_key_pem_file}" -pkeyopt rsa_padding_mode:pkcs1 \
  -out "${encrypted_password_file}" >/dev/null 2>&1
encrypted_password="$(base64 <"${encrypted_password_file}" | tr -d '\n')"
login_payload="$(SMOKE_USERNAME="${smoke_username}" \
  SMOKE_PASSWORD_CIPHERTEXT="${encrypted_password}" \
  python -c 'import json, os; print(json.dumps({"username": os.environ["SMOKE_USERNAME"], "password": os.environ["SMOKE_PASSWORD_CIPHERTEXT"]}))')"
login_json="$(docker exec -i "${app}" curl --fail --silent \
  --header 'Content-Type: application/json' --data-binary @- \
  http://127.0.0.1:4000/api/v1/auth/login <<<"${login_payload}")"
login_tokens="$(extract_token_pair <<<"${login_json}")"
read -r access_token refresh_token <<<"${login_tokens}"
[[ "${access_token}" =~ ^ey[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$ ]]
[[ "${refresh_token}" =~ ^ey[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$ ]]

refresh_json="$(docker exec -i "${app}" curl --fail --silent \
  --header 'Content-Type: application/json' --data-binary @- \
  http://127.0.0.1:4000/api/v1/auth/refresh <<<"{\"refreshToken\":\"${refresh_token}\"}")"
rotated_tokens="$(extract_token_pair <<<"${refresh_json}")"
read -r token rotated_refresh_token <<<"${rotated_tokens}"
[[ "${token}" =~ ^ey[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$ ]]
[[ "${rotated_refresh_token}" =~ ^ey[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$ ]]
[[ "${rotated_refresh_token}" != "${refresh_token}" ]]

old_refresh_status="$(docker exec -i "${app}" curl --silent --output /dev/null \
  --write-out '%{http_code}' --header 'Content-Type: application/json' --data-binary @- \
  http://127.0.0.1:4000/api/v1/auth/refresh <<<"{\"refreshToken\":\"${refresh_token}\"}")"
[[ "${old_refresh_status}" == "401" ]]
current_user_json="$(docker exec "${app}" curl --fail --silent \
  --header "Authorization: Bearer ${token}" \
  http://127.0.0.1:4000/api/v1/auth/me)"
python -c 'import json, sys; raise SystemExit(0 if json.load(sys.stdin).get("success") is True else 1)' \
  <<<"${current_user_json}"

docker stop "${postgres}" >/dev/null
for _attempt in $(seq 1 60); do
  health="$(docker inspect --format '{{.State.Health.Status}}' "${app}" 2>/dev/null || true)"
  if [[ "${health}" == "unhealthy" ]]; then
    break
  fi
  sleep 2
done

[[ "$(docker inspect --format '{{.State.Health.Status}}' "${app}")" == "unhealthy" ]]
docker start "${postgres}" >/dev/null

for _attempt in $(seq 1 60); do
  if docker exec "${postgres}" pg_isready -U postgres -d "${database}" >/dev/null 2>&1; then
    break
  fi
  sleep 2
done

docker exec "${postgres}" pg_isready -U postgres -d "${database}" >/dev/null
for _attempt in $(seq 1 60); do
  health="$(docker inspect --format '{{.State.Health.Status}}' "${app}" 2>/dev/null || true)"
  if [[ "${health}" == "healthy" ]]; then
    break
  fi
  sleep 2
done

[[ "$(docker inspect --format '{{.State.Health.Status}}' "${app}")" == "healthy" ]]
docker exec "${app}" sh -c 'printf smoke > /tmp/smoke.txt && printf smoke > /var/lib/keystone/resources/.smoke-persistence'
unauth_upload_status="$(docker exec "${app}" curl --silent --output /dev/null --write-out '%{http_code}' \
  --form file=@/tmp/smoke.txt http://127.0.0.1:4000/api/v1/file/upload)"
[[ "${unauth_upload_status}" == "401" ]]

upload_json="$(docker exec "${app}" curl --fail --silent \
  --header "Authorization: Bearer ${token}" \
  --form file=@/tmp/smoke.txt http://127.0.0.1:4000/api/v1/file/upload)"
upload_url="$(python -c 'import json, sys; print(json.load(sys.stdin)["data"]["url"])' <<<"${upload_json}")"
[[ "${upload_url}" == /profile/upload/* ]]

unauth_resource_status="$(docker exec "${app}" curl --silent --output /dev/null --write-out '%{http_code}' \
  http://127.0.0.1:4000"${upload_url}")"
[[ "${unauth_resource_status}" == "401" ]]
downloaded="$(docker exec "${app}" curl --fail --silent \
  --header "Authorization: Bearer ${token}" \
  http://127.0.0.1:4000"${upload_url}")"
[[ "${downloaded}" == "smoke" ]]

docker exec "${app}" curl --fail --silent http://127.0.0.1:4000/api/v1/health >/dev/null
docker exec "${app}" curl --fail --silent http://127.0.0.1:4000/api/v1/health/ready >/dev/null
docker exec "${app}" curl --fail --silent http://127.0.0.1:4000/api/v1/auth/rsa-public-key >/dev/null
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

# 撤销当前访问令牌的会话，并确认随后受保护请求返回 401。
logout_status="$(docker exec "${app}" curl --silent --output /dev/null --write-out '%{http_code}' \
  --request POST --header "Authorization: Bearer ${token}" \
  http://127.0.0.1:4000/api/v1/auth/logout)"
[[ "${logout_status}" == "200" ]]
post_logout_status="$(docker exec "${app}" curl --silent --output /dev/null --write-out '%{http_code}' \
  --header "Authorization: Bearer ${token}" \
  http://127.0.0.1:4000/api/v1/auth/me)"
[[ "${post_logout_status}" == "401" ]]

echo "release smoke passed for ${image}"
