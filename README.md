# Keystone Phoenix

Elixir/Phoenix rewrite project for [Keystone](https://github.com/bruceblink/Keystone).

The project is managed with Mix and uses PostgreSQL from the first commit.

## Toolchain

- Elixir 1.20.x
- Erlang/OTP 29.x
- Phoenix 1.8.16
- Ecto SQL 3.14.x
- Postgrex 0.22.x
- bcrypt_elixir 3.3.x
- JOSE 1.11.x
- Phoenix LiveView 1.2.x
- Bandit 1.14.x
- PostgreSQL 18.x

The dependency versions are locked in [`mix.lock`](mix.lock). `mix.exs` keeps
the compatible minor version ranges so security and patch releases can be
updated with the normal Mix workflow.

The current release baseline is `0.3.0`. Release tags are created only after
the production smoke checks in [`docs/04-deployment-runbook.md`](docs/04-deployment-runbook.md)
pass against the built image.

## Local development

```bash
cp .env.example .env
docker compose up -d postgres
mix setup
mix phx.server
```

The API listens on <http://localhost:4000>.

Useful Mix commands:

```bash
mix format
mix check.source_lines
mix test
mix precommit
mix ecto.create
mix ecto.migrate
mix ecto.rollback
MIX_ENV=prod mix release
```

Production releases can be built with the included multi-stage Dockerfile:

```bash
docker build -t keystone-phoenix:latest .
docker run --rm --env-file .env --entrypoint /app/bin/migrate keystone-phoenix:latest
docker run --rm --env-file .env -p 4000:4000 keystone-phoenix:latest start
```

GitHub Actions publishes release images to
`ghcr.io/bruceblink/keystone-phoenix` only for stable semantic version tags
such as `v0.3.0`. The image keeps the same `vX.Y.Z` tag and does not create
branch, commit, `latest`, or unprefixed semver aliases. The workflow validates
the tag before pushing and keeps BuildKit layers in the GitHub Actions cache.

The release reads `DATABASE_URL`, `SECRET_KEY_BASE`, `JWT_PRIVATE_KEY`, and
`PHX_HOST` at runtime. Use `/health` for liveness and `/health/ready` for
PostgreSQL readiness; rebuildable cache data is kept in the local ETS store.
Production enables PostgreSQL TLS by default. Set `DATABASE_SSL_ALLOW_INSECURE=true` only for a trusted local test network; optionally set
`DATABASE_SSL_CA` to a CA bundle path. `POOL_SIZE` and `POOL_COUNT` control
the PostgreSQL connection pools. `AUTH_SESSION_CLEANUP_INTERVAL_MS` and
`MONITOR_SNAPSHOT_INTERVAL_MS` control the OTP cleanup and monitoring workers.
Scheduler polling and task concurrency can be adjusted with `JOB_SCHEDULER_INTERVAL_MS`,
`JOB_TASK_MAX_CHILDREN`, and `JOB_EXECUTION_TIMEOUT_MS`.

The frontend is being rebuilt with Phoenix LiveView. The existing Keystone
frontend can continue calling the JSON endpoints while LiveView owns the new
server-rendered interactive pages and Ecto owns PostgreSQL access.

The current frontend reference is
[bruceblink/keystone-frontend](https://github.com/bruceblink/keystone-frontend).
The current `main` branch is the usable replacement baseline. The reference
frontend remains useful for API compatibility checks, while LiveView owns the
new interactive pages; visual 1:1 parity is not a release requirement.

Implemented API slices currently include health checks, dictionary type/data
CRUD, ETS-backed dictionary lookups, and system configuration CRUD with
validated option values and cache refresh support. User list/detail queries and
default local accounts are also available as the foundation for authentication.
Local login, RS256 access/refresh tokens, refresh rotation, single-account
session control, and protected user queries are now available through
`/api/v1/auth/login`, `/api/v1/auth/refresh`, `/api/v1/auth/me`, and
`/api/v1/system/users`. The `/api/v1/auth/rsa-public-key` endpoint returns a
Base64 encoded X.509 public key; clients encrypt the login password with
RSA/PKCS#1 before sending `/api/v1/auth/login`.

Administrator access tokens can also create, update, soft-delete, disable, and
reset passwords for local users through the write endpoints under
`/api/v1/system/users`. Passwords are validated and bcrypt-hashed before persistence;
disabling, deleting, or resetting a user revokes that user's active refresh
session. Management endpoints use the role menu permission strings from
`sys_role_menu`; administrator access bypasses those checks and other roles are
constrained by their configured data scope.

The organization and permission foundation now includes PostgreSQL-backed
departments, posts, roles, menus, role-menu assignments, and the authenticated
`/api/v1/auth/routers` menu tree. Read endpoints are available under
`/api/v1/system/depts`, `/api/v1/system/post`, `/api/v1/system/role`, and
`/api/v1/system/menus`. Departments and posts also
support role-permission checked create, update, and soft-delete commands; role
and menu resources also support permission checked update, status, data scope,
menu assignment, and soft-delete commands. Data-scope checks cover all data,
custom departments, the current department tree, the current department, and
the current user. Role users can be queried and assigned or unassigned in bulk
under the role grant endpoints.

Authenticated users can read and update their own profile under
`/api/v1/system/user/profile`, including old-password-checked password changes and
avatar URL updates, and `POST /api/v1/system/user/profile/avatar` accepts the original
`avatarfile` multipart upload and stores profile resources under `FILE_BASE_DIR`.
User create and update commands validate referenced
departments, posts, and roles before writing.

Administrators can manage notices through `/api/v1/system/notices` with paginated
queries, detail reads, create, update, and soft-delete operations.

Generic file upload/download endpoints, user/post/role/log Excel export, user
Excel import/template download, and dictionary cache refresh are available
under the `/api/v1` prefix. `/api/v1/auth/logout` revokes the current access
token's PostgreSQL-backed session, while
`/api/v1/auth/logout-refresh-token` remains available for clients that only
have a refresh token.

The log foundation now provides permission-protected login and operation log
queries and cleanup under `/api/v1/logs`; authenticated users can submit operation log
records for their own actions. All authenticated POST, PUT, PATCH, and DELETE
management requests also create an operation record on the server, with
passwords, tokens, captcha values, and upload paths redacted. Login success and
failure results are recorded without passwords or tokens.

Public login bootstrap endpoints now include `/api/v1/auth/config` and
`/api/v1/auth/captcha`. The seeded configuration keeps captcha disabled, and setting
`sys.account.captchaOnOff` to `true` enables ETS-backed, one-time math or
character GIF captchas selected with `CAPTCHA_TYPE`. `/api/v1/auth/login` consumes the
captcha key before checking credentials. `/api/v1/auth/register` returns an explicit
unsupported response until an open-registration policy is implemented.

MFA HTTP endpoints use the same `/api/v1/auth` namespace. A password login for an
account that requires MFA returns a short-lived challenge; the client completes it
with `POST /api/v1/auth/mfa/verify`. Authenticated administrators can enroll a TOTP factor,
verify enrollment, rotate recovery codes, update a user's MFA policy, and create or
verify a session-bound step-up challenge through the corresponding `/mfa/*` endpoints.
Recovery codes and TOTP secrets are returned only from the enrollment or rotation
request that creates them.

API Key 管理使用 `/api/v1/api-keys`。创建、读取、轮换和撤销分别需要 `api-key:create`、
`api-key:read`、`api-key:rotate` 和 `api-key:revoke`。密钥使用 `ks_live_<prefix>_<secret>`
格式，明文只在创建或轮换响应中返回；数据库只保存 SHA-256 摘要。每次 API Key 认证都会
把密钥批准范围与用户当前权限求交集。

Administrator monitoring endpoints now cover ETS cache metrics at
`/api/v1/monitor/cacheInfo`, BEAM host metrics at `/api/v1/monitor/serverInfo`,
current online sessions backed by PostgreSQL at `/api/v1/monitor/onlineUsers`,
and forced logout at `DELETE /api/v1/monitor/onlineUser/:tokenId`. The network
status endpoint emits a server-sent event snapshot at
`/api/v1/monitor/networkStatus/stream`, which the
frontend can reconnect to as needed.

Scheduled job management is available through `/api/v1/system/jobs`, including
allow-listed invocation targets, job definition CRUD, enable/disable status,
manual execution, and execution logs at `/api/v1/system/jobs/logs`. Manual execution
uses the same persisted log format that the scheduler will use for automatic
Cron triggers.

Public configuration, captcha, and RSA public-key endpoints use ETS-backed
per-node rate limits. Notice creation uses a per-user repeat-submission guard;
expired authentication sessions are removed by an OTP worker.

The LiveView login page is available at `/`. It keeps the authenticated user
and refresh session on the LiveView process and provides a server-side logout
action. The dashboard is split into organization, account, system, and
operations components, covering departments, posts, roles, menus, users,
profiles, configuration, dictionaries, notices, logs, scheduled jobs, and
monitoring. Phoenix and LiveView browser assets are served from their Mix
dependencies, so the page does not need a separate Node.js build step. Every
source file is kept at 600 lines or fewer and the limit is checked by CI.

## PostgreSQL and ETS configuration

Development and test configuration reads `POSTGRES_*` environment variables.
Dictionary lookups by type use ETS with a five-minute TTL; writes invalidate
the corresponding key. Refresh token sessions are stored in the PostgreSQL
`auth_sessions` table, so sessions survive application restarts and can be
shared by multiple application instances. Production releases require
`DATABASE_URL` and `SECRET_KEY_BASE` from the runtime environment. Production
authentication also requires the PEM encoded
`JWT_PRIVATE_KEY` value; `JWT_PUBLIC_KEY` is optional and is derived from the
private key when omitted. The private key signs JWTs and decrypts RSA login
passwords. Development generates an ephemeral RSA key pair when those values
are omitted. No database password is committed to the repository.

ETS is local to one BEAM node and is used only for data that can be rebuilt,
such as captcha challenges and dictionary/configuration caches. The session
table remains the source of truth for authentication and online-user control.

The seeded development users use password `123456`; replace those credentials
before exposing a deployment outside local development.
