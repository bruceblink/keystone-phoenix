# Keystone Phoenix 0.3.0 部署手册

本文用于验证 release image、初始化 PostgreSQL 和执行回滚前检查。生产 secret 只通过环境变量或 secret manager 注入，不写入仓库。

## 构建和迁移

在项目根目录构建镜像：

```bash
docker build -t keystone-phoenix:0.3.0 .
```

默认从 Docker Hub 官方地址读取 Elixir 和 Debian 基础镜像，从 Hex 官方地址读取依赖，并在两个阶段从 Debian 官方软件源读取软件包。Hex 包继续按 `mix.lock` 校验，Debian 软件包继续验证软件源签名。

Excel 依赖使用已固定提交的兼容版本；`vendor/xlsxir` 只保留必要的编译 warning 修正。构建阶段使用 `mix compile --warnings-as-errors`，不会通过关闭全局 warning 检查来隐藏依赖问题。

本地网络需要国内镜像时，可以显式切换基础镜像和 Debian 软件源；这些参数不写入默认配置：

```bash
docker build \
  --build-arg IMAGE_REGISTRY=m.daocloud.io/docker.io/library/ \
  --build-arg DEBIAN_MIRROR=http://mirrors.tuna.tsinghua.edu.cn \
  -t keystone-phoenix:0.3.0 .
```

如果国内基础镜像或 Hex 镜像不可用，可显式使用 Docker Hub 和官方 Hex 地址：

```bash
docker build --build-arg IMAGE_REGISTRY= --build-arg HEX_MIRROR=https://repo.hex.pm \
  -t keystone-phoenix:0.3.0 .
```

准备生产环境文件，至少包含 `DATABASE_URL`、`SECRET_KEY_BASE`、`JWT_PRIVATE_KEY`、`PHX_HOST` 和 `FILE_BASE_DIR`。生产默认启用数据库 SSL；只有在可信本地网络测试时才显式设置 `DATABASE_SSL_ALLOW_INSECURE=true`。生产运行时默认要求 `PHX_FORCE_SSL=true`。如果通过反向代理传入 `x-forwarded-proto`，必须同时配置 `TRUSTED_PROXY_CIDRS`，应用只信任这些来源地址。直接使用 HTTPS 时不需要配置代理来源。如果必须在本地使用 HTTP，必须同时设置 `PHX_FORCE_SSL=false` 和 `PHX_ALLOW_INSECURE_HTTP=true`；这两个设置不能用于生产流量。`CORS_ALLOWED_ORIGINS` 使用逗号分隔的完整来源地址，生产来源必须使用 `https://`，留空表示不允许跨域读取。应用启动前会检查 `FILE_BASE_DIR` 可创建、可写和可删除，也会拒绝无效的 CORS 来源、代理 CIDR 和不安全的 HTTP 配置。PostgreSQL 已经可用后，先执行迁移：

```bash
docker run --rm \
  --env-file .env \
  --entrypoint /app/bin/migrate \
  keystone-phoenix:0.3.0
```

迁移脚本只执行尚未完成的 Ecto migration，重复执行是安全的。新数据库需要显式执行种子数据；生产环境不要直接使用开发种子密码。

## 启动和 smoke 检查

启动应用并暴露 4000 端口。生产环境必须提供 `JWT_PRIVATE_KEY`、`MFA_MASTER_KEY` 和至少 16 字节的
`MFA_RECOVERY_PEPPER`；MFA 密钥版本使用 `MFA_MASTER_KEY_VERSION` 管理：

```bash
docker run -d --name keystone-phoenix \
  --env-file .env \
  -p 4000:4000 \
  keystone-phoenix:0.3.0 start
```

依次检查存活、数据库就绪、LiveView 首页和安全响应头：

```bash
curl --fail http://127.0.0.1:4000/api/v1/health
curl --fail http://127.0.0.1:4000/api/v1/health/ready
curl --fail http://127.0.0.1:4000/
curl --fail --include http://127.0.0.1:4000/api/v1/health | grep -E 'x-content-type-options|x-frame-options|referrer-policy|content-security-policy'
```

发布 smoke 还需要在临时环境停止 PostgreSQL，确认 `/api/v1/health/ready` 返回失败且容器健康状态变为 `unhealthy`；恢复 PostgreSQL 后，确认数据库就绪和容器健康状态恢复为 `healthy`。仓库中的 `scripts/release_smoke.sh` 会自动执行这组检查。

认证 smoke 流程应覆盖：获取 `/api/v1/auth/rsa-public-key`，使用 RSA 公钥登录，调用 `/api/v1/auth/me` 和 `/api/v1/auth/routers`，刷新 `/api/v1/auth/refresh`，最后调用 `/api/v1/auth/logout`。还必须检查标准 `/api/.well-known/jwks.json` 返回唯一的 RSA JWK，并确认 `kid`、`alg`、`use`、`n` 和 `e` 字段有效。启用验证码时还要先验证 `/api/v1/auth/config` 和 `/api/v1/auth/captcha`。`scripts/release_smoke.sh` 会验证 MFA 管理入口对 API Key 和未认证请求的拒绝；完整 TOTP enrollment、恢复码一次性消费和 step-up 成功链路由集成测试和独立运行验收覆盖。

API Key smoke 流程应使用具有 `api-key:create`、`api-key:read`、`api-key:revoke`、`user:read` 和 `mfa:manage` 的 Bearer 用户调用 `/api/v1/api-keys`，确认创建响应只返回一次明文，列表不返回明文或摘要，使用 API Key 的业务用户查询成功，MFA、人类会话和 API Key 管理路径返回 `403 permission_denied`，撤销后认证失败。轮换行为由集成测试和独立运行验收覆盖。

资源范围 smoke 使用管理员的 `ALL` 范围验证一条允许的业务路径。管理员 smoke 不代表非管理员拒绝规则已经通过镜像链路验证；`data_scope_denied` 的 `SELF`、`DEPARTMENT`、`DEPARTMENT_AND_CHILDREN`、`CUSTOM` 和资源组合矩阵由集成测试和真实 HTTP 验收覆盖。

文件 smoke 流程应上传一个允许的头像和一个普通文本/PDF 文件，确认头像可以通过 `/profile/...` 内联返回，普通文件可以下载，并确认不存在路径穿越。

## PostgreSQL 备份和恢复

备份应在发布前和数据库迁移前执行：

```bash
pg_dump --format=custom "$DATABASE_URL" > keystone-$(date -u +%Y%m%dT%H%M%SZ).dump
```

恢复到临时数据库后再切换流量：

```bash
createdb keystone_restore_check
pg_restore --clean --if-exists --dbname=keystone_restore_check keystone-*.dump
```

恢复检查至少确认迁移版本、`sys_user`、`sys_role`、`sys_menu`、`auth_sessions` 和文件目录仍然可读。文件目录需要单独备份；数据库备份不包含 `FILE_BASE_DIR` 中的上传文件。

## 回滚

先停止新容器并保留数据库和上传目录，再启动上一版本镜像。不要回滚已经执行过的迁移，除非对应 migration 有经过验证的 down 操作；优先使用向前兼容的应用版本修复。认证会话表保留，必要时用户重新登录即可。

`v0.3.0` 已完成 smoke、签名和生产窗口验收。后续版本沿用同一流程：完成独立环境 smoke 后创建并推送对应的 `vX.Y.Z` tag，由 GitHub Actions 构建并发布 GHCR 镜像。
