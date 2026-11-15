# Native 与 Phoenix 接口验收矩阵

正式版本的同一份 admin-web 必须能够替换连接 Native 或 Phoenix。发布验收条件、双后端页面流程和证据要求见 [`10-admin-web-backend-interchangeability-acceptance.md`](10-admin-web-backend-interchangeability-acceptance.md)。

## 术语和命名

| 术语 | English | 职责和边界 |
| --- | --- | --- |
| 接口路径 | endpoint path | HTTP 方法与 URL 的组合。本文只记录 `/api/v1` 对外入口。 |
| 响应结构 | DTO | `success`、`data`、`message`、`error` 信封内的字段结构。路径一致不表示 DTO 一致。 |
| AAL2 | Authentication Assurance Level 2 | 已完成当前会话二次认证的短时访问令牌。账号启用 `mfa_required` 或入口使用 `enforce=true` 时，写操作必须使用 AAL2。 |

## 已完成的路径和权限对齐

Native 作为 HTTP 入口基准，Phoenix 已完成以下路径处理：

- 删除 Native 没有的用户导入模板、部门详情、岗位详情、菜单详情、角色详情、旧字典读取、角色状态和数据范围入口。
- 删除旧 `/system/*` 和 `/logs/*` 管理路径，保留 Native 同样存在的登录日志和操作日志删除入口。
- 保留并补齐任务单项删除 `DELETE /api/v1/jobs/{id}`。
- 补齐菜单角色绑定 `PUT /api/v1/menus/{id}/roles`。
- 对齐公告公开读取、管理读取和发布：
  `GET /api/v1/notices`、`GET /api/v1/notices/manage`、
  `POST /api/v1/notices/{id}/publish`。
- 用户、角色、API Key、在线会话下线和个人密码写操作按账号的 `mfa_required` 策略检查；用户导入、Passkey 注册和 MFA 管理入口使用 `enforce=true`，始终要求 AAL2。API Key 不进入人类认证路径。
- Native 的任务触发路径 `/api/v1/jobs/{id}/trigger` 已删除旧的重复 `/run` 入口。

Phoenix 证据：`mix phx.routes` 未发现 `/system`、`/logs`、`auth/passkey`、`health/ready`、`monitor/networkStatus` 和用户导入模板旧入口。路由和权限修改已在 `f8d3db9` 提交。

### 路由集合验收

2026-11-15 对两个后端的业务路由做了静态集合核对。Native 的 JAX-RS 类级路径与
`quarkus.http.root-path=/api` 合并后，再与 Phoenix 的 `mix phx.routes` 结果比较；参数
占位符 `{id}` 与 `:id` 先归一为同一形状。两边均有 109 条业务路由，方法分布均为
`GET 41`、`POST 29`、`PUT 20`、`DELETE 19`。归一化后 Native-only 和 Phoenix-only
业务路由均为 0，也没有重复的 `HTTP method + path`。Phoenix 额外的 3 条 GET 路由是
LiveView 页面和头像资源，不属于后端业务接口。

Native 还有 `/api/openapi` 和 `/api/swagger` 文档入口。它们由 Quarkus 生成，不纳入
业务接口集合。参数占位符的语言差异不表示接口缺失。

## DTO 和数据模型验收结果

Phoenix HTTP 控制器现在按 Native/admin-web 的响应结构返回数据。用户、角色、部门、岗位、菜单、配置、字典、公告、任务、审计、个人资料和监控均有对应的字段适配和回归测试。列表接口按 Native 约定返回数组或 `items/page/size/total`，创建和更新返回实体，删除返回 `deleted`，任务触发返回 `triggered`。

为保存 Native 所需的业务字段，新增并应用了部门编码、菜单编码、菜单排序、配置启用状态、任务编码和字典字符串值迁移。部门和菜单保留旧 LiveView 原始写入的数据库触发器。任务编码另有更高版本修复迁移，覆盖“迁移记录已存在但列未创建”的旧安装状态。

仍有三个明确边界：Phoenix 用户表只有一个 `role_id`，HTTP 写入支持零个或一个 `roleCodes`，多个角色编码返回校验错误；Phoenix 任务列表的 `lastStatus` 和 `lastRunAt` 没有独立持久化来源，返回空值；Phoenix 的 BEAM 运行时按 Native 监控字段提供结构化结果，Java 专属含义不适用。以上边界不会静默丢弃请求字段。

## UI 验收边界

Native 与 admin-web 的真实 HTTP 联调已经覆盖健康检查、RSA 公钥、登录、监控、角色、API Key、登出和 AAL2 step-up。admin-web 当前正式页面构建的 `pnpm test:run`、`pnpm typecheck` 和 `pnpm build` 均通过。Phoenix 当前提交的 `mix test --include integration` 通过 374 项；`mix format --check-formatted`、`mix compile --warnings-as-errors`、`mix check.source_lines` 和 `git diff --check` 均通过。Native 当前提交执行 `./gradlew test --no-daemon` 返回 `BUILD SUCCESSFUL`。

个人资料密码更新已与 Native/admin-web 接口对齐：`PUT /api/v1/profile/password` 在 AAL2 会话中接收单个 `password` 字段，并在成功后撤销当前会话。Phoenix LiveView 个人资料页也只显示新密码字段。

Phoenix MFA parity 已在 `a5d5320` 完成：普通敏感写操作按账号的 `mfa_required` 策略检查 step-up，用户导入和 Passkey 注册使用 `enforce=true`，始终要求 AAL2 step-up。该策略与 Native 的接口行为保持一致。

### 真实窗口和 HTTP 验收记录

2026-11-15 在本机分别启动 Native、Phoenix 和同一份 admin-web 构建。Native 使用 MySQL 8.4，Phoenix 使用本地 PostgreSQL；页面代理通过 `VITE_ENABLE_MOCK=false` 切换 `http://127.0.0.1:8080` 与 `http://127.0.0.1:4000`。

- Native 已完成真实 HTTP smoke：健康检查、登录、监控、在线会话、用户、角色、组织、岗位、菜单、API Key、配置、字典、通知、任务、登录日志、操作审计、个人资料和注销均返回预期成功状态；`GET /api/v1/dictionaries` 与 `GET /api/v1/notices/manage` 使用 admin-web 的正式路径验证通过。该证据证明接口可用，不等同于真实浏览器页面通过。
- Native 的真实浏览器页面矩阵已完成：在端口 `5175` 的 admin-web 使用 `admin/password` 登录成功，监控、用户、角色、组织、岗位、菜单、API Key、审计、登录日志、定时任务、配置、字典、通知和个人资料页面均能通过侧栏或头像入口打开；通知按钮进入通知公告，监控帮助可以展开和关闭。Native admin-web 在 280、320、390、768 和 1280 视口的 `document` 与 `body` 宽度均等于视口宽度，未发现横向溢出。用户页面还完成了一次真实新增和删除：密码策略错误反馈后改用合规密码创建唯一测试用户，列表刷新后选择该用户、打开删除确认并完成删除，随后清理测试数据。
- 同一份 admin-web 使用 `ag1/123456` 登录 Phoenix 成功。运行监控、用户、角色、组织、岗位、菜单、API Key、配置、字典、公告、登录日志、操作审计、定时任务和个人资料页面均通过真实导航打开；个人资料只从顶栏用户图形进入，侧栏不显示“工作台”和个人资料菜单。
- Phoenix 补充窗口记录：同一份 admin-web 在 `VITE_API_PROXY_TARGET=http://127.0.0.1:4000`、前端端口 `5176` 下使用 `ag1/123456` 登录成功；13 个可见菜单页面、通知入口、顶栏用户图形入口、监控帮助展开和关闭均通过验收，并在 280、320、390、768 和 1280 视口完成宽度矩阵检查。

- Phoenix LiveView 已按 admin-web 的共享壳和页面组件结构重实现。已验证深色页面令牌、流式侧栏和内容区、统一卡片、筛选表格、徽标、模态框、用户图形个人资料入口，以及侧栏移除“工作台”、个人资料菜单和“系统”分组标题。内置浏览器在 280、320、390、768 和 1280 视口验证了 Phoenix 无横向溢出，顶栏上下文不换行，内容区随视口拉伸；窄屏侧边抽屉可以打开，选择导航后自动收起。当前可见 LiveView 菜单为 13 项；`/dashboard` 和旧任务日志状态保留为兼容路径或内部分支，不作为侧栏菜单。Native admin-web 已完成同样的真实浏览器宽度矩阵，两个后端均保留逐页写操作、筛选、导出、批量操作、空态、错误反馈和模态框结果验收项。
- 监控页按 Vercel Dashboard 的信息密度重新打磨：状态栏、健康摘要、主证据图表、资源卡片、在线会话和节点详情保持统一层级。admin-web 趋势图增加 80% 关注阈值和数据来源，空趋势显示“暂无采样数据”；Phoenix 当前采样图使用同样的阈值、来源和空态语义，缺失指标显示 `—`，不再显示为 `0%`。监控帮助交互对应 admin-web `379d7f8`、Phoenix `c4f39bd`；admin-web 当前测试为 17 个文件、72 项通过；Phoenix `mix test --include integration` 为 374 项通过，Native 和 Phoenix 真实窗口均已在 280、320、390、768 和 1280 视口检查横向溢出。

本次验收仍有明确限制：监控页的部分指标由 Native 接口未提供，页面应显示后端来源和未提供指标；页面通过不表示缺失指标已经补齐。Native 和 Phoenix 已完成真实读取、导航和响应式宽度检查；Native 用户新增、选择、删除确认和清理已完成，Phoenix 通过同一 admin-web 的对应用户流程记录已完成。除该用户流程外，其他筛选、导出、批量删除、加载状态、错误反馈、模态框和写操作仍需按页面逐项记录。MFA 登录挑战已覆盖接口和前端错误兼容测试，但本次没有触发真实 MFA 挑战；OIDC、公钥硬件 Passkey、CSRF/Cookie、多节点和生产代理链不属于本地窗口验收，不能据此判定通过。
