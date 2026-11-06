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

GitHub Actions publishes the same release image to
`ghcr.io/bruceblink/keystone-phoenix` for every `main` push and `v*` tag. The
workflow also supports manual runs from the Actions tab and keeps BuildKit
layers in the GitHub Actions cache.

The release reads `DATABASE_URL`, `SECRET_KEY_BASE`, `JWT_PRIVATE_KEY`, and
`PHX_HOST` at runtime. Use `/health` for liveness and `/health/ready` for
PostgreSQL readiness; rebuildable cache data is kept in the local ETS store.
Set `DATABASE_SSL=true` for verified PostgreSQL TLS and optionally set
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
It remains usable during the first migration phase while the equivalent
LiveView pages are added to this repository at the same API boundaries.

Implemented API slices currently include health checks, dictionary type/data
CRUD, ETS-backed dictionary lookups, and system configuration CRUD with
validated option values and cache refresh support. User list/detail queries and
default local accounts are also available as the foundation for authentication.
Local login, RS256 access/refresh tokens, refresh rotation, single-account
session control, and protected user queries are now available through `/login`,
`/refresh-token`, `/getLoginUserInfo`, and `/system/users`. The
`/login/rsa-public-key` endpoint returns a Base64 encoded
X.509 public key; clients encrypt the login password with RSA/PKCS#1 before
sending `/login`, matching the original Keystone contract.

Administrator access tokens can also create, update, soft-delete, disable, and
reset passwords for local users through the write endpoints under
`/system/users`. Passwords are validated and bcrypt-hashed before persistence;
disabling, deleting, or resetting a user revokes that user's active refresh
session. The system configuration and dictionary management endpoints use the
same administrator check. Non-administrator access tokens receive `403` for
these management endpoints.

The organization and permission foundation now includes PostgreSQL-backed
departments, posts, roles, menus, role-menu assignments, and the authenticated
`/getRouters` menu tree. Read endpoints are available under `/system/depts`,
`/system/post`, `/system/role`, and `/system/menus`. Departments and posts also
support role-permission checked create, update, and soft-delete commands; role
and menu resources also support permission checked update, status, data scope,
menu assignment, and soft-delete commands. Data-scope checks cover all data,
custom departments, the current department tree, the current department, and
the current user. Role users can be queried and assigned or unassigned in bulk
under the role grant endpoints.

Authenticated users can read and update their own profile under
`/system/user/profile`, including old-password-checked password changes and
avatar URL updates, and `POST /system/user/profile/avatar` accepts the original
`avatarfile` multipart upload and stores profile resources under `FILE_BASE_DIR`.
User create and update commands validate referenced
departments, posts, and roles before writing.

Administrators can manage notices through `/system/notices` with paginated
queries, detail reads, create, update, and soft-delete operations.

Generic file upload/download endpoints, user/post/role/log Excel export, user
Excel import/template download, and dictionary cache refresh are available at
the same paths as the Java application. `/logout` revokes the current access
token's PostgreSQL-backed session, while `/logout-refresh-token` remains
available for clients that only have a refresh token.

The log foundation now provides administrator-only login and operation log
queries and cleanup under `/logs`; authenticated users can submit operation log
records for their own actions. All authenticated POST, PUT, PATCH, and DELETE
management requests also create an operation record on the server, with
passwords, tokens, captcha values, and upload paths redacted. Login success and
failure results are recorded without passwords or tokens.

Public login bootstrap endpoints now include `/getConfig` and
`/captchaImage`. The seeded configuration keeps captcha disabled, and setting
`sys.account.captchaOnOff` to `true` enables ETS-backed, one-time math or
character GIF captchas selected with `CAPTCHA_TYPE`. `/login` consumes the
captcha key before checking credentials. `/register` returns an explicit
unsupported response until an open-registration policy is implemented.

Administrator monitoring endpoints now cover ETS cache metrics at
`/monitor/cacheInfo`, BEAM host metrics at `/monitor/serverInfo`, current online
sessions backed by PostgreSQL at `/monitor/onlineUsers`, and forced logout at
`DELETE /monitor/onlineUser/:tokenId`. The network status endpoint emits a
server-sent event snapshot at `/monitor/networkStatus/stream`, which the
frontend can reconnect to as needed.

Scheduled job management is available through `/system/jobs`, including
allow-listed invocation targets, job definition CRUD, enable/disable status,
manual execution, and execution logs at `/system/jobs/logs`. Manual execution
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
