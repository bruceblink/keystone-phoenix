# Keystone Phoenix

Keystone Phoenix 是 Keystone 的 Elixir、Phoenix 和 Phoenix LiveView 后端。项目从第一版开始使用 PostgreSQL，并提供 JSON API、LiveView 管理页面、认证、权限、审计和后台任务能力。

Phoenix 以 [Keystone Admin Web](https://github.com/bruceblink/keystone-admin-web) 为页面和交互基准。LiveView 在 Phoenix 内重新实现 admin-web 的页面结构、布局、查询、表单、通知和响应式行为，不直接复用 React 页面代码。

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

当前主线按 `v1.0.0` 发布目标维护。正式发布标签只在
[`docs/04-deployment-runbook.md`](docs/04-deployment-runbook.md) 中记录的生产 smoke 检查通过后创建。

## 1.0.0 生产配套

Phoenix 只提供管理后台后端，不能单独作为完整的生产管理系统运行。生产部署必须将 Phoenix 与同一版本的 [Keystone Admin Web](https://github.com/bruceblink/keystone-admin-web) 绑定：

- 标准组合为 `admin-web v1.0.0 + Phoenix v1.0.0`。admin-web 提供管理页面，Phoenix 提供 `/api/v1` 服务、LiveView 页面、数据库迁移和运行时能力。
- `admin-web v1.0.0 + Native v1.0.0` 是可替换的后端组合。切换前必须重新完成接口、权限、错误码、登录、通知、查询、写操作和窄屏布局验收。
- 只部署 Phoenix 而不部署 admin-web，或将 Phoenix 与未验收的前端构建包混用，均不满足生产发布条件。

前端 API 代理或 API 基地址必须指向选定的 Phoenix 服务。前端构建包、Phoenix 镜像和 PostgreSQL 迁移必须来自同一发布验收批次。Native 1.0 发布后只维护缺陷、安全问题和依赖兼容性，新增业务功能主要进入 Phoenix 主线。

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

生产镜像由 GitHub Actions 发布工作流构建。开发机不构建生产镜像。正式
`vX.Y.Z` 标签发布后，使用 CI 构建的镜像执行迁移并启动服务：

```bash
docker pull ghcr.io/bruceblink/keystone-phoenix:1.0.0
docker run --rm --env-file .env --entrypoint /app/bin/migrate ghcr.io/bruceblink/keystone-phoenix:1.0.0
docker run --rm --env-file .env -p 4000:4000 ghcr.io/bruceblink/keystone-phoenix:1.0.0 start
```

GitHub Actions 只为稳定语义版本标签发布
`ghcr.io/bruceblink/keystone-phoenix`。镜像使用不带 `v` 的 `X.Y.Z` 标签，例如
`1.0.0`，不创建分支、提交、`latest` 或带 `v` 的别名。工作流会校验 Git 标签，构建并签名镜像，生成 SBOM 和 provenance，执行远端 smoke，并创建 GitHub Release。BuildKit 层使用 GitHub Actions 缓存。

The release reads `DATABASE_URL`, `SECRET_KEY_BASE`, `JWT_PRIVATE_KEY`, and
`PHX_HOST` at runtime. Use `/api/v1/health` for liveness; rebuildable cache
data is kept in the local ETS store.
Production enables PostgreSQL TLS by default. Set `DATABASE_SSL_ALLOW_INSECURE=true` only for a trusted local test network; optionally set
`DATABASE_SSL_CA` to a CA bundle path. `POOL_SIZE` and `POOL_COUNT` control
the PostgreSQL connection pools. `AUTH_SESSION_CLEANUP_INTERVAL_MS` and
`MONITOR_SNAPSHOT_INTERVAL_MS` control the OTP cleanup and monitoring workers.
Scheduler polling and task concurrency can be adjusted with `JOB_SCHEDULER_INTERVAL_MS`,
`JOB_TASK_MAX_CHILDREN`, and `JOB_EXECUTION_TIMEOUT_MS`.

Phoenix LiveView 是 Phoenix 的正式管理页面实现。admin-web 是页面结构、文案、交互和 `/api/v1` 行为的基准，LiveView 必须在 Phoenix 中重新实现这些页面。发布验收需要覆盖导航、登录、通知、查询条件、分页、加载、空数据、错误、重试、编辑、删除、批量操作、详情和响应式布局。

Native 与 Phoenix 共用 admin-web 的后端接口约定。两套后端可以替换同一份 admin-web，但替换前需要验证版本对应的接口、权限范围、业务错误码和页面闭环。Phoenix LiveView 的样式和布局也必须与 admin-web 的验收基准保持一致。

Implemented API slices currently include health checks, dictionary type/data
CRUD, ETS-backed dictionary lookups, and system configuration CRUD with
validated option values and cache refresh support. User list/detail queries and
default local accounts are also available as the foundation for authentication.
Local login, RS256 access/refresh tokens, refresh rotation, single-account
session control, and protected user queries are now available through
`/api/v1/auth/login`, `/api/v1/auth/refresh`, `/api/v1/profile`, and
`/api/v1/users`. The `/api/v1/auth/rsa-public-key` endpoint returns a
Base64 encoded X.509 public key; clients encrypt the login password with
RSA/PKCS#1 before sending `/api/v1/auth/login`.

Administrator access tokens can also create, update, soft-delete, disable, and
reset passwords for local users through the write endpoints under
`/api/v1/users`. Passwords are validated and bcrypt-hashed before persistence;
disabling, deleting, or resetting a user revokes that user's active refresh
session. Management endpoints use the role menu permission strings from
`sys_role_menu`; administrator access bypasses those checks and other roles are
constrained by their configured data scope.

The organization and permission foundation now includes PostgreSQL-backed
departments, posts, roles, menus, role-menu assignments, and the authenticated
`/api/v1/menus` menu tree. Read endpoints are available under
`/api/v1/departments`, `/api/v1/posts`, `/api/v1/roles`, and
`/api/v1/menus`. Departments and posts also
support role-permission checked create, update, and soft-delete commands; role
and menu resources also support permission checked update, status, data scope,
menu assignment, and soft-delete commands. Data-scope checks cover all data,
custom departments, the current department tree, the current department, and
the current user. Role users can be queried and assigned or unassigned in bulk
under the role grant endpoints.

Authenticated users can read and update their own profile under
`/api/v1/profile`, including old-password-checked password changes and
avatar URL updates, and `PUT /api/v1/profile/avatar` accepts the original
`avatarfile` multipart upload and stores profile resources under `FILE_BASE_DIR`.
User create and update commands validate referenced
departments, posts, and roles before writing.

Public clients read published and enabled notices from `/api/v1/notices`.
Administrators read scoped notice metadata from `/api/v1/notices/manage` and
use `/api/v1/notices`, `/api/v1/notices/{id}`, and
`/api/v1/notices/{id}/publish` for create, update, publish, and delete
operations.

Generic file upload/download endpoints, user/post/role/log Excel export, and user
Excel import are available
under the `/api/v1` prefix. `/api/v1/auth/logout` revokes the current access
token's PostgreSQL-backed session.

The log foundation now provides permission-protected login and operation log
queries and cleanup under `/api/v1/login-logs` and `/api/v1/operation-logs`; authenticated users can submit operation log
records for their own actions. All authenticated POST, PUT, PATCH, and DELETE
management requests also create an operation record on the server, with
passwords, tokens, captcha values, and upload paths redacted. Login success and
failure results are recorded without passwords or tokens.

Initial-password recovery uses `/api/v1/auth/change-initial-password`. It verifies
the current password, requires the stored initial-password flag, updates the password,
and revokes the user's active sessions.

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
and forced logout at `DELETE /api/v1/monitor/onlineUser/:tokenId`.

Scheduled job management is available through `/api/v1/jobs`, including
allow-listed invocation targets, job definition CRUD, enable/disable status,
manual execution, and execution logs at `/api/v1/jobs/logs`. Manual execution
uses the same persisted log format that the scheduler will use for automatic
Cron triggers.

RSA public-key endpoints use ETS-backed per-node rate limits. Notice creation uses
a per-user repeat-submission guard;
expired authentication sessions are removed by an OTP worker.

The LiveView login page is available at `/`. It keeps the authenticated user
and refresh session on the LiveView process and provides a server-side logout
action. The dashboard is split into organization, account, system, and
operations components, covering departments, posts, roles, menus, users,
profiles, configuration, dictionaries, notices, logs, scheduled jobs, and
monitoring. Phoenix and LiveView browser assets are served from their Mix
dependencies, so the page does not need a separate Node.js build step. Every
source file is kept at 600 lines or fewer and the limit is checked by CI.

## 页面和接口验收

LiveView 管理壳从 `/` 登录页进入，使用侧边导航访问运行监控、用户、角色、部门、岗位、菜单与权限、API Key、接口文档、配置、字典、通知、登录日志、操作审计、定时任务和个人资料。通知铃铛只显示当前用户的站内通知，点击列表项后显示通知详情。

JSON API 统一使用 `/api/v1` 前缀和 `{success, data, message, error}` 响应结构。登录和刷新使用 `data.accessToken`、`data.refreshToken`，API Key 只在创建或轮换响应中返回明文。业务错误使用唯一业务错误码，HTTP 状态码保持接口约定不变。

发布前至少执行以下检查：

```bash
mix format --check-formatted
mix check.source_lines
MIX_ENV=prod mix compile --warnings-as-errors
mix test
mix test --include integration
```

发布工作流还会验证正式标签、数据库迁移可重复执行、备份恢复、认证、刷新令牌轮换、JWK、API Key 范围、文件和健康检查，随后执行镜像 smoke、Cosign、SBOM、provenance 和 GitHub Release 资产核验。公网 IdP、硬件 Passkey、多节点恢复、生产 TLS/代理链和生产发布窗口仍需在目标环境单独验收。

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
