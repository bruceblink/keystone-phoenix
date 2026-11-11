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

准备生产环境文件，至少包含 `DATABASE_URL`、`SECRET_KEY_BASE`、`JWT_PRIVATE_KEY`、`PHX_HOST` 和 `FILE_BASE_DIR`。生产默认启用数据库 SSL；只有在可信本地网络测试时才显式设置 `DATABASE_SSL_ALLOW_INSECURE=true`。应用启动前会检查 `FILE_BASE_DIR` 可创建、可写和可删除。PostgreSQL 已经可用后，先执行迁移：

```bash
docker run --rm \
  --env-file .env \
  --entrypoint /app/bin/migrate \
  keystone-phoenix:0.3.0
```

迁移脚本只执行尚未完成的 Ecto migration，重复执行是安全的。新数据库需要显式执行种子数据；生产环境不要直接使用开发种子密码。

## 启动和 smoke 检查

启动应用并暴露 4000 端口：

```bash
docker run -d --name keystone-phoenix \
  --env-file .env \
  -p 4000:4000 \
  keystone-phoenix:0.3.0 start
```

依次检查存活、数据库就绪和 LiveView 首页：

```bash
curl --fail http://127.0.0.1:4000/health
curl --fail http://127.0.0.1:4000/health/ready
curl --fail http://127.0.0.1:4000/
```

发布 smoke 还需要在临时环境停止 PostgreSQL，确认 `/health/ready` 返回失败且容器健康状态变为 `unhealthy`；恢复 PostgreSQL 后，确认数据库就绪和容器健康状态恢复为 `healthy`。仓库中的 `scripts/release_smoke.sh` 会自动执行这组检查。

认证 smoke 流程应覆盖：获取 `/login/rsa-public-key`，使用 RSA 公钥登录，调用 `/getLoginUserInfo` 和 `/getRouters`，刷新 `/refresh-token`，最后调用 `/logout`。启用验证码时还要先验证 `/getConfig` 和 `/captchaImage`。

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

完成 smoke 检查后，再创建并推送 `v0.3.0` tag，让 GitHub Actions 构建并发布 GHCR 镜像。
