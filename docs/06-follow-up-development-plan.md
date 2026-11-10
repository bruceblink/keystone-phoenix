# Keystone Phoenix 完整审查后的后续开发计划

计划基线：`8c09eee`。本文保存完整审查后的后续开发计划。

## 审查结论

当前 HEAD 为 `8c09eee`，工作区干净。现有功能覆盖认证、权限、组织管理、文件、Excel、任务、监控和 LiveView 页面，主要高风险问题已修复。

仍存在以下问题：

- **授权入口不一致**：配置、字典、公告、岗位、任务、日志和部分监控 HTTP 写入口仍按菜单权限放行；LiveView 对应操作仍偏向管理员限制。下拉接口部分 action 没有权限映射，任意 Bearer 用户可能读取。
- **配置和数据校验缺口**：`isAllowChange=false` 仍可更新；字典数据不验证字典类型；Excel 表头不验证允许列、必需列和重复列；角色批量 ID 会静默丢弃非法值；外链菜单不验证 host。
- **任务和运行时边界**：手动任务超时仍存在 `Task.shutdown` 竞态；readiness 不检查 ETS；Docker healthcheck 只检查端口；自定义 `FILE_BASE_DIR` 可能不可写；生产数据库 SSL 默认关闭。
- **容量与安全边界**：登录限流 ETS 没有最大条目数；LiveView 登录限流没有绑定 IP；批量文件没有总大小上限；监控接口暴露部署路径、启动参数和挂载点。
- **前端完整性**：表格没有 caption、空状态和滚动语义；500 条上限仍会静默截断；刷新、执行和状态切换缺少统一加载锁；角色刷新或删除后保留旧的角色用户状态；上传错误暴露 `inspect(entry)`。
- **测试和发布缺口**：默认测试存在并发不稳定记录；控制器覆盖不足；`mix test --cover` 约 56%–63%，低于当前 90% 阈值；没有自动 release、Docker、备份恢复和持久卷 smoke；文档仍有旧提交、旧测试数字和旧构建描述。

## 实施顺序

### 1. 统一细粒度权限模型

采用已确认的“**仅权限控制**”策略：

- HTTP 和 LiveView 的管理写操作都按明确 action permission 控制，不增加统一管理员门槛。
- 完整补齐 `dropdown`、字典按类型查询、缓存刷新、日志删除、任务执行、监控强制下线等 action 的权限映射。
- `Authenticate.permission_allowed?/3` 在 controller 已声明权限表但 action 缺失时返回拒绝，避免漏配 action 默认放行。
- 将 LiveView 当前 `admin_socket?` 写操作改为对应 permission 检查，保持 HTTP 与 LiveView 行为一致。
- 角色分配、日志读取和监控读取继续使用明确权限；按已确认策略，拥有权限的角色可以读取对应范围的数据。
- 为每个 controller 建立成功、未登录、无权限、参数错误、目标不存在五类 contract tests。

### 2. 修复领域校验和数据一致性

- 更新配置前检查旧值的 `is_allow_change`，不可修改配置返回明确的 422 错误。
- 字典数据创建和更新必须引用存在且未删除的字典类型。
- Excel 导入严格验证表头：允许集合、必需列、重复列和列顺序；错误在导入入口直接返回。
- 角色批量分配遇到任意非法 ID 时整批失败，不再静默过滤。
- 外链菜单要求 `http` 或 `https` 且必须有非空 host。
- 先执行现有数据差异检查，再追加必要外键迁移：角色菜单、字典类型、任务日志、用户关联字段和审计关联字段。软删除字段的 FK 行为写入迁移说明。

### 3. 收紧认证、上传和容量边界

- LiveView 登录限流使用 `peer_data` 获取客户端地址，与 HTTP 使用同一 IP+用户名限流模型。
- 为限流 ETS 增加最大条目配置。新 key 达到上限时先清理过期项，仍不足则返回服务不可用，不允许无限增长。
- 上传增加总批次大小上限，建议设置为 100 MiB；同时配置 multipart body 上限并在接口错误中区分单文件超限与批次超限。
- 监控 `server_info` 脱敏 `home`、`userDir`、`inputArgs` 和磁盘挂载路径，只保留必要运行指标。
- seeds 增加环境保护，生产环境必须显式阻止开发种子和默认密码执行。
- 加入登录限流故障、限流容量、Excel 表头、上传批次、监控脱敏和 seeds 环境保护测试。

### 4. 修复任务、健康检查和发布运行时

- 手动任务超时路径检查 `Task.shutdown/2` 返回值：任务已完成时以任务结果为准，不追加超时日志；只有确认任务终止且没有最终结果时才写超时日志。
- 给手动任务增加快速完成、恰好超时、取消与完成同时发生的回归测试，保证每次执行只有一条最终日志。
- `Health.readiness/0` 同时检查 PostgreSQL 和 RuntimeStore 的三个 ETS 表；任一依赖不可用返回 NOT_READY。
- Docker healthcheck 改为请求 `/health/ready`，并验证 PostgreSQL 故障时容器状态变为 unhealthy。
- 对 `FILE_BASE_DIR` 做启动前可写性检查；支持自定义挂载目录时由 entrypoint 创建并授权，失败时明确报错。
- 生产默认启用数据库 SSL；只有显式设置 `DATABASE_SSL_ALLOW_INSECURE=true` 时才允许关闭。
- 发布工作流加入临时 PostgreSQL、重复迁移、readiness、RSA 登录、文件上传下载、卷重启和非 root 用户 smoke。
- 锁定基础镜像、PostgreSQL 和 GitHub Actions 的 digest；缓存 key 纳入 Elixir、OTP、`mix.exs` 和 `mix.lock`。

### 5. 完善 LiveView 页面和交互

- 所有管理表格增加 caption、空状态消息和 `aria-live` 状态。
- 表格滚动区域增加 `tabindex="0"`、`aria-label` 和可感知的滚动说明。
- 将用户、日志、任务、字典、角色用户等分页数据改为真正分页，显示总数、当前页和上一页/下一页，不再静默截断 500 条。
- 角色刷新、删除和保存后清空 `selected_role_id`、角色名称和已分配/未分配用户列表。
- 为刷新、执行、取消、状态切换和上传按钮增加 `phx-disable-with`。
- 将上传错误映射为稳定的中文提示，不直接渲染 `inspect(entry)`。
- 为表单错误增加字段关联和 `aria-describedby`。
- 将内嵌 CSS 和 LiveSocket 初始化脚本拆到静态资源，降低 `login_live.ex` 维护压力；拆分后保持 600 行限制。

## 测试和交付

- 先修复 `PasswordSessionControllerTest` 的 DDL fixture：使用唯一函数/触发器名称，并在 `on_exit` 清理；连续运行默认测试至少 5 次，确认没有 deadlock。
- 建立 controller contract matrix，分批覆盖 Config、Dictionary、Department、Menu、Post、Notice、Role、Job、Log、File、Health、Profile 和 Monitor。
- 增加 `Release.migrate`、readiness、Docker 非 root、healthcheck、持久卷和备份恢复自动化测试。
- 覆盖率先记录默认和集成基线，再按模块逐步提高；第一阶段设置 60% 以上的可执行门槛，后续随 controller matrix 增长，不直接使用当前 90% 全仓门槛阻断开发。
- 每个独立切片执行格式检查、严格编译、源码行数检查、定向测试、默认测试和集成测试。
- 每个通过验证的独立切片创建一个范围明确的提交并立即推送，最后再更新开发计划、审查记录和 README。

## 默认假设

- 继续采用单节点部署，ETS 不承担跨节点共享。
- 保留现有 HTTP 路径和主要响应字段；新增错误码只用于新增失败边界。
- 细粒度权限由 action permission 控制，日志和配置遵循“拥有对应权限即可访问”的已确认策略。
- 不在本阶段引入 MySQL ETL、多节点调度或外部缓存服务。
- 真实浏览器窗口工具和标准 registry 构建恢复后，再完成最终发布验收和版本标签创建。

## 2026-11-10 实施状态

本计划的代码修复已完成并按独立切片提交推送。权限入口已统一为显式 action permission，字典缓存刷新使用 `system:dict:refresh`；配置不可变、字典引用、Excel 表头、角色批量 ID、外链 host 和完整性外键校验已落地。限流容量、批量上传总量、监控脱敏、生产 seeds 保护、数据库 SSL 默认策略和 `FILE_BASE_DIR` 启动可写性检查已完成。任务超时竞态、PostgreSQL/ETS readiness、Docker healthcheck、release smoke、备份恢复、卷重启、非 root、SBOM、provenance 和 Cosign 检查已纳入代码或发布工作流；基础镜像、PostgreSQL 和 GitHub Actions 已固定到 digest/提交 SHA。LiveView 表格无障碍语义、真实分页、角色状态清理、统一按钮禁用反馈和静态资源拆分已完成。

本轮相关提交包括：`c12935d`、`2e5642a`、`2c48bcd`、`6650a8b`、`94bb456`、`7bd3990`、`740bf6e` 和 `a4aac22`。监控在线会话现在使用服务端分页，角色主列表也使用全量分页聚合；刷新、强制下线和页码切换会同步总数与当前页。验证结果为：默认测试连续 5 次均为 151 项通过、20 项排除；`mix test --include integration` 为 171 项通过；`mix test --cover --include integration` 为 171 项通过、总覆盖率 65.24%；格式检查、源码行数检查、严格编译和 `git diff --check` 均通过。

剩余验收只涉及环境和发布动作：本机 Docker release 构建因 Hex registry TLS CA 环境问题未完成，未通过关闭 TLS 校验绕过；真实浏览器窗口验收和最终 GHCR 构建、签名、版本标签仍需在具备 registry 与浏览器环境后执行。
