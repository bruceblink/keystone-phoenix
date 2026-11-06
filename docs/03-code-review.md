# Keystone Phoenix 代码审查与后续计划

审查基于 2026-11-06 的 `main`，范围包括 Phoenix/Ecto 领域层、HTTP API、LiveView、PostgreSQL 迁移、OTP worker、Docker 和 GitHub Actions，并以 `Keystone` Java 项目和 `keystone-frontend` 的实际调用方式作为行为参考。

## 当前结论

项目已经达到“可部署、可用、可以继续迭代”的第一阶段基线。核心认证、组织权限、系统管理、日志、文件、Excel、定时任务和 LiveView 页面都有可执行实现；Redis 已移除，持久化状态由 PostgreSQL 保存，可重建的短期数据由本节点 ETS 保存。当前版本不追求 Java 实现或旧前端视觉上的 1:1 复制。

代码质量满足当前迭代约束：所有 `lib`、`config`、`priv`、`test` 下的 Elixir 源文件不超过 600 行，最大的文件为 `login_live.ex`（535 行）。全局 Codex 配置已写入“每个独立功能完成后先提交并推送”的要求，后续切片按这个边界推进。

已完成的审查修复包括：

- 上传的 PDF、文本和 Office 文件可以通过 `/profile/*path` 下载，图片仍以内联方式返回，并保留路径穿越、扩展名、大小和文件签名校验。
- 菜单 DTO 同时提供 `id`、布尔 `isButton`、`menuTypeStr`、`statusStr`、`rank` 和 `icon`；角色详情提供 `selectedMenuList` 与 `selectedDeptList`，并支持 `isButton` 查询过滤。
- 部门 DTO 提供前端树所需的 `id` 和 `statusStr`，岗位 DTO 提供 `statusStr`。
- 用户列表、当前登录用户和个人资料提供部门、岗位、角色及审计人名称；个人资料返回前端需要的 `{user, roleName, postName}` 结构。
- 字典默认值按前端约定输出 `0/1`，并兼容布尔、数字和字符串输入。

## 已验证范围

- `mix precommit`：严格编译、依赖清理、格式检查、源文件行数检查和默认测试。
- `mix test --include integration`：PostgreSQL 数据测试、权限检查、LiveView 集成和 API 契约测试。
- `MIX_ENV=prod mix compile --warnings-as-errors`：生产环境严格编译。
- `MIX_ENV=prod mix release`：OTP release 可组装，Docker 多阶段构建路径完整。
- CI 已覆盖 PostgreSQL 18、默认测试、集成测试和 GHCR release image 构建。

## 风险和待办

### P0：发布准备

`mix.exs` 仍为 `0.2.0`，仓库的 `v0.2.0` 标签早于最近的功能修复。下一次发布前需要把版本提升到 `0.3.0`（或明确的实际版本），重新生成 release image，执行空库迁移和种子启动检查，并验证 `/health/ready`、登录、刷新、退出、文件下载和 LiveView 首页。

生产环境必须通过 secret 注入 `DATABASE_URL`、`SECRET_KEY_BASE` 和 `JWT_PRIVATE_KEY`；PostgreSQL TLS、连接池、文件目录和 worker 间隔已经支持环境变量，但还需要一份可执行的部署与备份恢复手册。

### P1：接口和数据语义收敛

1. 为 `keystone-frontend` 的每个 API 模块补充 HTTP 契约测试，覆盖状态码、响应字段、分页、筛选、批量 ID 参数和文件下载响应，避免只依赖领域层测试。
2. 补齐创建者/更新者写入：公告、配置、字典、组织、岗位、角色和任务目前主要由领域函数直接写入，审计字段应统一从认证用户注入；公告列表也应返回 `creatorName`。
3. 对齐剩余 DTO 细节：日志列表补充 Java DTO 中的状态、业务类型和操作人标签；用户详情接口补齐角色/岗位选项；配置和日志 ID 的字符串/数字表示统一。
4. 对真实前端执行一次登录、菜单树、角色授权、用户列表、个人资料、字典和文件上传/下载联调，保留失败用例作为回归测试。

### P2：OTP、数据库和观测优化

1. 调度器增加任务定义缓存失效策略，清理 `last_trigger` 中已删除任务的键，避免长期运行时状态增长；为手动执行、超时、取消和跳过补充并发测试。
2. 使用 Telemetry 记录请求耗时、数据库连接池、任务执行耗时/结果、ETS 命中率和会话清理数量，并为健康检查保留低开销路径。
3. 复核 PostgreSQL 索引和分页查询，尤其是会话过期、日志时间范围、用户部门范围和角色菜单连接；把重复的分页、状态过滤和参数转换抽到小型领域 helper。
4. 让 LiveView 页面按角色权限隐藏或禁用不可用操作。API 已经执行权限和数据范围校验，但管理 LiveView 目前主要按管理员入口限制。

### P3：可选迁移和工程化

1. 对仍在 MySQL 上运行的旧 Keystone 提供可重复执行的 `sys_*` ETL/导入工具，明确 ID、时间、软删除、密码和字典值的转换规则。
2. 增加浏览器级 smoke 测试和 release image 启动测试；单节点部署继续使用 ETS，多节点部署前先设计共享临时状态策略。
3. 在完成行为稳定后，再拆分接近 600 行的 LiveView/领域模块，并优先采用 pattern matching、管道和 context 边界，避免为了形式重构改变 API 行为。

## 推荐执行顺序

每个编号作为一个可独立验收的切片，完成后执行格式、严格编译、源文件行数、默认测试和集成测试，再单独提交并推送：

1. 发布硬化：版本、迁移/种子 smoke、部署手册和 `v0.3.0` release。
2. API 契约测试与剩余 DTO 对齐。
3. 审计字段和公告/日志展示语义统一。
4. 调度器状态清理、并发测试和 Telemetry 指标。
5. PostgreSQL 索引、查询 helper 和 LiveView 权限感知。
6. 可选 MySQL ETL、浏览器测试和多节点方案评估。

当前不需要重新引入 Redis；会话表是认证事实来源，ETS 只保存丢失后可以重建的验证码、字典/配置缓存和本节点限流状态。
