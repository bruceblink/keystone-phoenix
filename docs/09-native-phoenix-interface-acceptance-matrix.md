# Native 与 Phoenix 接口验收矩阵

正式版本的同一份 admin-web 必须能够替换连接 Native 或 Phoenix。发布验收条件、双后端页面流程和证据要求见 [`10-admin-web-backend-interchangeability-acceptance.md`](10-admin-web-backend-interchangeability-acceptance.md)。

## 术语和命名

| 术语 | English | 职责和边界 |
| --- | --- | --- |
| 接口路径 | endpoint path | HTTP 方法与 URL 的组合。本文记录 `/api/v1` 业务入口和标准 JWK Set `/api/.well-known/jwks.json`。 |
| 响应结构 | DTO | `success`、`data`、`message`、`error` 信封内的字段结构。路径一致不表示 DTO 一致。 |
| AAL2 | Authentication Assurance Level 2 | 已完成当前会话二次认证的短时访问令牌。账号启用 `mfa_required` 或入口使用 `enforce=true` 时，写操作必须使用 AAL2。 |

## 已完成的路径和权限对齐

Native 作为 HTTP 入口基准，Phoenix 已完成以下路径处理：

- 删除 Native 没有的用户导入模板、部门详情、岗位详情、菜单详情、角色详情、旧字典读取、角色状态和数据范围入口。
- 删除旧 `/system/*` 和 `/logs/*` 管理路径；审计接口只保留 Native 同样存在的查询和导出入口。
- 保留并补齐任务单项删除 `DELETE /api/v1/jobs/{id}`。
- 补齐菜单角色绑定 `PUT /api/v1/menus/{id}/roles` 和查询 `GET /api/v1/menus/{id}/roles`。
- 菜单管理主体通过 `GET /api/v1/menus` 读取完整的未删除多级菜单树，包括停用和未绑定节点；普通菜单读取仍只返回已启用且已绑定节点。
- 对齐公告公开读取、管理读取和发布：
  `GET /api/v1/notices`、`GET /api/v1/notices/manage`、
  `POST /api/v1/notices/{id}/publish`。
- 用户、角色、API Key、在线会话下线和个人密码写操作按账号的 `mfa_required` 策略检查；用户导入、Passkey 注册和 MFA 管理入口使用 `enforce=true`，始终要求 AAL2。API Key 不进入人类认证路径。
- Native 的任务触发路径 `/api/v1/jobs/{id}/trigger` 已删除旧的重复 `/run` 入口。

Phoenix 证据：`mix phx.routes` 未发现 `/system`、`/logs`、`auth/passkey`、`health/ready`、`monitor/networkStatus` 和用户导入模板旧入口。路由和权限修改已在 `f8d3db9` 提交。

### 路由集合验收

2026-11-15 对两个后端的业务路由做了静态集合核对。Native 的 JAX-RS 类级路径与
`quarkus.http.root-path=/api` 合并后，再与 Phoenix 的 `mix phx.routes` 结果比较；参数
占位符 `{id}` 与 `:id` 先归一为同一形状。两边均有 108 条 `/api/v1` 接口（含
`/api/v1/health`），方法分布均为 `GET 42`、`POST 29`、`PUT 20`、`DELETE 17`。归一化后
Native-only 和 Phoenix-only 接口均为 0，也没有重复的 `HTTP method + path`。Phoenix 额外的 3 条 GET 路由是
LiveView 页面和头像资源，不属于后端业务接口。

标准 JWK Set 另有 `/api/.well-known/jwks.json` 1 条路径。健康接口用于运行状态检查，但属于 `/api/v1` 接口集合，不单独重复计数。

Native 还有 `/api/openapi` 和 `/api/swagger` 文档入口。Phoenix 提供相同的 `/api/openapi`
和 `/api/swagger` 兼容入口，admin-web 的“接口文档”菜单统一打开 `/api/swagger`。这些文档
入口由各后端生成，不纳入业务接口集合。参数占位符的语言差异不表示接口缺失。

## DTO 和数据模型验收结果

Phoenix HTTP 控制器现在按 Native/admin-web 的响应结构返回数据。用户、角色、部门、岗位、菜单、配置、字典、公告、任务、审计、个人资料和监控均有对应的字段适配和回归测试。列表接口按 Native 约定返回数组或 `items/page/size/total`，创建和更新返回实体，删除返回 `deleted`，任务触发返回 `triggered`。

为保存 Native 所需的业务字段，新增并应用了部门编码、菜单编码、菜单排序、配置启用状态、任务编码和字典字符串值迁移。部门和菜单保留旧 LiveView 原始写入的数据库触发器。任务编码另有更高版本修复迁移，覆盖“迁移记录已存在但列未创建”的旧安装状态。

仍有三个明确边界：Phoenix 用户表只有一个 `role_id`，HTTP 写入支持零个或一个 `roleCodes`，多个角色编码返回校验错误；Phoenix 任务列表的 `lastStatus` 和 `lastRunAt` 没有独立持久化来源，返回空值；Phoenix 的 BEAM 运行时按 Native 监控字段提供结构化结果，Java 专属含义不适用。以上边界不会静默丢弃请求字段。

## UI 验收边界

Native 与 admin-web 的真实 HTTP 联调已经覆盖健康检查、RSA 公钥、登录、监控、角色、API Key、登出和 AAL2 step-up。admin-web 当前正式页面构建的 `pnpm test:run`（86 项）、`pnpm typecheck` 和 `pnpm build` 均通过。Phoenix 当前提交的 `mix test --include integration` 通过 410 项；`mix format --check-formatted`、`mix compile --warnings-as-errors`、`mix check.source_lines` 和 `git diff --check` 均通过。Native 当前提交执行 `./gradlew test --no-daemon --rerun-tasks` 返回 `BUILD SUCCESSFUL`，菜单接口专项 HTTP 测试也通过。

个人资料密码更新已与 Native/admin-web 接口对齐：`PUT /api/v1/profile/password` 在 AAL2 会话中接收单个 `password` 字段，并在成功后撤销当前会话。Phoenix LiveView 个人资料页也只显示新密码字段。用户和任务列表 DTO 已在 Phoenix `61511e7` 收敛为 Native canonical 字段，旧字段不会通过兼容合并继续返回。

Phoenix MFA parity 已在 `a5d5320` 完成：普通敏感写操作按账号的 `mfa_required` 策略检查 step-up，用户导入和 Passkey 注册使用 `enforce=true`，始终要求 AAL2 step-up。该策略与 Native 的接口行为保持一致。

### 真实窗口和 HTTP 验收记录

2026-11-15 在本机分别启动 Native、Phoenix 和同一份 admin-web 构建。Native 使用 MySQL 8.4，Phoenix 使用本地 PostgreSQL；页面代理通过 `VITE_ENABLE_MOCK=false` 切换 `http://127.0.0.1:8080` 与 `http://127.0.0.1:4000`。

- Native 已完成真实 HTTP smoke：健康检查、登录、监控、在线会话、用户、角色、组织、岗位、菜单、API Key、配置、字典、通知、任务、登录日志、操作审计、个人资料和注销均返回预期成功状态；`GET /api/v1/dictionaries` 与 `GET /api/v1/notices/manage` 使用 admin-web 的正式路径验证通过。该证据证明接口可用，不等同于真实浏览器页面通过。
- Native 的真实浏览器页面矩阵已完成：在端口 `5175` 的 admin-web 使用 `admin/password` 登录成功，监控、用户、角色、组织、岗位、菜单、API Key、审计、登录日志、定时任务、配置、字典、通知和个人资料页面均能通过侧栏或头像入口打开；通知公告通过独立菜单访问，监控帮助可以展开和关闭。新通知铃铛的站内列表/详情逻辑已由代码和测试覆盖，双后端真实窗口待补。Native admin-web 在 280、320、390、768 和 1280 视口的 `document` 与 `body` 宽度均等于视口宽度，未发现横向溢出。用户页面还完成了一次真实新增和删除：密码策略错误反馈后改用合规密码创建唯一测试用户，列表刷新后选择该用户、打开删除确认并完成删除，随后清理测试数据。
- 同一份 admin-web 使用 `ag1/123456` 登录 Phoenix 成功。运行监控、用户、角色、组织、岗位、菜单、API Key、配置、字典、公告、登录日志、操作审计、定时任务和个人资料页面均通过真实导航打开；个人资料只从顶栏用户图形进入，侧栏不显示“工作台”和个人资料菜单。
- Phoenix 补充窗口记录：同一份 admin-web 在 `VITE_API_PROXY_TARGET=http://127.0.0.1:4000`、前端端口 `5176` 下使用 `ag1/123456` 登录成功；可见菜单已增至 14 项并包含“接口文档”，其余页面、通知公告入口、顶栏用户图形入口、监控帮助展开和关闭均通过验收，并在 280、320、390、768 和 1280 视口完成宽度矩阵检查。新通知铃铛的列表/详情和活动会话登录确认尚未补双后端真实窗口记录。Swagger 菜单的 `/api/swagger` 和 `/api/openapi` 路由由 Phoenix 控制器测试覆盖。
- 本次真实窗口复核补充了 Phoenix 岗位页：岗位列表、无结果筛选、重置、每页状态、新增弹窗打开和取消关闭均通过；页面显示“系统 API”来源，未发现横向溢出。
- 本次真实窗口复核补充了 Phoenix 角色页：当前结果集全选后删除按钮显示“删除角色（2）”并启用，取消一项后显示“删除角色（1）”，无结果筛选后选择状态清空并显示“删除角色（0）”；1280 和 390 视口的文档宽度均与视口一致。对应提交为 `41a9517`。
- 同一份 admin-web 连接 Phoenix 的真实窗口复核补充了通知公告页：全选 2 条公告后删除按钮显示“删除公告（2）”并启用，无结果筛选后显示空态并清空为“删除公告（0）”；1280 和 390 视口的文档宽度均与视口一致。
- Phoenix 通知公告页已补齐 admin-web 的当前结果集全选、单项选择、删除数量按钮、批量确认和筛选/刷新后的选择清理；删除仍复用 `Notice.delete_notices([ids])`，对应提交为 `4588322`。LiveView 集成测试验证了全选数量、清空选择、单项删除和其他公告保留。
- Phoenix 字典页的未选择类型状态已与 admin-web 对齐：显示“字典条目”“选择类型后查看条目。”、“选择类型后维护”和“选择一个字典类型”；选择类型后保留条目表格和分页，提交为 `39c74c5`。字典类型筛选现在同时匹配名称和编码，无匹配时清空条目选择并显示左右两侧空态，提交为 `1c4b108`。
- Phoenix LiveView 真实窗口复核补充了字典页：输入无匹配类型后，左侧显示“没有匹配的字典类型”，右侧显示“选择一个字典类型”和“选择类型后维护”；1280 和 390 视口的文档宽度均与视口一致。多级菜单页同时显示了按层级缩进的菜单目录。
- 任务页已按 admin-web 对齐暂停任务的交互：停用任务的“执行”按钮带 `disabled`，LiveView 事件也返回错误反馈；Native 和 Phoenix 的 `/jobs/{id}/trigger` HTTP 接口继续保留既有直接触发约定，不因页面禁用改变后端接口语义。Phoenix 对应提交为 `da6a27a`、`735eb7e`，Native 全量测试 `222` 项通过。
- 本次真实窗口复核创建临时暂停任务后验证了 Phoenix 任务页：1280 和 390 视口下暂停任务行的“执行”按钮均为禁用状态，文档宽度与视口一致；临时任务、会话和浏览器进程已清理。
- Phoenix 通知页已补齐 `notice_filter` 和 `selected_notice_ids` 到 LiveView 组件的赋值，筛选和批量选择状态不再被默认赋值覆盖，对应提交为 `3a2efab`。真实窗口输入无匹配标题后显示“没有匹配的公告”，不渲染空表头。
- Phoenix LiveView 已将用户、部门、岗位、角色、菜单、配置和任务页面的筛选、选择及当前详情状态显式传给组件；筛选输入和批量操作状态不会在事件后回退到默认值。用户筛选值和删除按钮状态由集成测试验证，对应提交为 `fa66fff`。
- Phoenix 菜单页已按 admin-web 基准展开任意层级菜单树，兼容 `nil`、`0`、`"0"` 和混合类型父级 ID；深层筛选保留祖先节点，表格使用响应式层级缩进，并在编辑父级选择中排除自身和后代。对应提交为 `763feb7`。
- 本次内置浏览器复核使用真实 Phoenix 服务和 `ag1/123456`：菜单筛选 `user:read` 显示“系统管理”根节点和“用户管理”子节点，用户筛选 `ag1` 保留输入值并在选择后显示“删除用户（1）”；1280 视口的文档宽度为 1280，390 窄屏的文档和 body 宽度均为 390，侧栏抽屉可以打开且页面没有横向溢出。菜单表格在窄屏内部滚动，不扩大页面宽度。
- Phoenix 菜单编辑弹窗已补齐 admin-web 的“可访问角色”复选框，只展示启用角色；编辑时读取现有绑定，保存时替换绑定，空选择会清除绑定。LiveView 集成测试覆盖读取、保存、重新打开和清空，对应提交为 `86a9114`。角色绑定失败时保留编辑弹窗和表单状态。
- Phoenix 菜单 LiveView 现在兼容 Native 的 `enabled` 布尔字段和 `MENU`、`BUTTON`、`DIRECTORY` 字符串类型，同时保留 Phoenix 的 `status` 和整数类型映射；菜单状态与类型展示已补充组件和数据测试，随提交 `c04db24` 验证。
- Native/admin-web 真实窗口复核补充了登录加载状态、错误密码反馈、用户筛选和批量选择、角色编辑取消、菜单多级筛选祖先保留，以及 390 窄屏文档/body 宽度检查。Native 使用 MySQL 8.4 和端口 8080；admin-web 代理目标必须显式使用 `http://127.0.0.1:8080`，否则登录请求会返回 502。
- admin-web 响应式壳已补齐中等窄视口断点：侧栏在 390 和 768 视口切换为抽屉，监控区域切换为单列；1280 视口保留桌面双列。登录页在 390、768、1280 视口分别使用单列、单列和双列布局。真实 Chrome 验证三种宽度的 document/body 均等于视口且无横向溢出，对应提交为 admin-web `3e01da7`；Phoenix 已在 `b6b12ac` 移植相同的登录页收缩规则，并在 `7f86d43`、`21a0ce2`、`953a8fb` 对齐原生壳结构、抽屉行为和 `68.75rem` 响应式断点。
- Native 菜单树读取已补充 `menu:read` 权限检查；无该权限的已认证主体访问 `GET /v1/menus` 返回 `403 permission_denied`，对应提交为 Native `ef129ea`。Phoenix 个人资料读取、更新、头像和密码更新已分别要求 `user:read`、`user:update`、`user:update` 和 `user:reset-password`，对应提交为 `4ea659f`，并补充受限主体 HTTP 回归。
- Native 已删除 Phoenix 和 admin-web 都不使用的 `DELETE /v1/login-logs?ids=...` 与 `DELETE /v1/operation-logs?ids=...`，同步删除旧权限目录项并增加 `V57__remove_audit_log_delete_permissions.sql`；admin-web 继续使用读取和导出接口。对应提交为 Native `a7e33bb`，定向权限测试和全量 `./gradlew test --no-daemon` 均通过。
- Phoenix 已删除岗位更新控制器中无法由现行路由触发的 `postId` 参数分支，并将权限测试迁移到 Native/admin-web 使用的规范字段；对应提交为 `a2a6ea4`，定向测试 9 项通过。Phoenix 和 Native 现仅保留 admin-web 使用的批量参数：用户/角色 `ids`、公告 `notice_ids`、任务 `jobIds`；旧别名返回 422 `validation_failed`。对应提交为 Phoenix `592ceb5`、Native `591ac88`。Phoenix 角色成员接口进一步删除 `user_ids`、`roleId`/`:role_id` 兼容字段和旧 `{total, rows}` 分页响应，统一使用 `userIds` 和用户 ID 数组，对应提交为 `84d8988`。任务列表、用户列表和任务日志也已删除旧 `{rows,total}`/`rows` 响应字段，统一使用 Native 的数组和 `items` 结构，对应提交为 `fde3b9e`。
- Phoenix 角色成员分配和移除现在与 Native 一样统一使用 `role:assign`；之前控制器传入的 `role:update` 已删除，角色范围集成测试在只授予 `role:assign` 时通过。对应提交为 `c45871a`。
- Phoenix LiveView 角色页面的用户分配和移除事件也已改为检查并传递 `role:assign`，与 HTTP 接口和 Native 权限边界一致；LiveView 管理集成测试通过，对应提交为 `5e5c759`。
- Phoenix 角色控制器的 `unassign_users` 权限声明也已统一为 `role:assign`，避免内部动作声明和 Native/HTTP 权限边界不一致；角色权限回归测试通过，对应提交为 `bfda55e`。

- Native 和 Phoenix 的同一份 admin-web 还完成了真实筛选和模态框检查：角色、组织、岗位、菜单、API Key、操作审计、登录日志、系统配置和字典页面使用无结果条件查询后显示空态，再点击“重置”恢复列表；用户、角色、组织、岗位、菜单、系统配置、字典、通知和定时任务的新增弹窗均能打开并取消关闭。两端的页面标题、查询按钮、空态和弹窗关闭结果一致。
- Native 和 Phoenix 的用户、角色、岗位、操作审计和登录日志页面均通过真实“导出 Excel”检查，下载操作没有显示错误反馈。Phoenix 角色导出的 `406` 已在 `220fdde` 修复：API 管道现在接受 XLSX MIME，并登记 `xlsx` 格式。
- Native 和 Phoenix 的角色页、Native 任务页还完成了选择记录、打开批量删除确认并取消的真实窗口检查，未执行删除。
- Native 和 Phoenix 的角色、组织、岗位页面均完成真实新增、列表显示、删除确认和测试数据清理。Phoenix 未登记菜单权限的错误已从 500 修复为 422 `validation_failed`，对应提交为 `55e92fe`；API Key 缺失和重复轮换状态已在 `b3a1af9` 对齐 Native。菜单非法 UUID 的 422/404 边界已在 `c39f335` 和 `47a26a1` 对齐 Native。
- API Key 授权范围已改为动态目录选择：Native `884a9cb`、`2376eb0`，Phoenix `50e1828`、`80e0f39`、`0a8a547` 提供 `GET /api/v1/permissions/catalog`，目录读取要求 `api-key:create`，返回权限标识、资源、动作、说明、风险和当前主体 `allowed` 状态；admin-web `090dc21` 与 Phoenix LiveView `7a8e16f`、`380aa63` 新增“配置接口权限”入口，按资源分组搜索并逐项选择，提交时只发送允许的 `scopes`。真实 Chrome 已验证 Phoenix 后端目录加载、`user:read` 搜索、逐项勾选和 390 宽度无横向溢出。

- Phoenix LiveView 已按 admin-web 的共享壳和页面组件结构重实现。已验证深色页面令牌、流式侧栏和内容区、统一卡片、筛选表格、徽标、模态框、用户图形个人资料入口，以及侧栏移除“工作台”、个人资料菜单和“系统”分组标题。LiveView 壳已改为 `app-shell`、`sidebar`、`shell-content`、`topbar`、`shell-main` 原生结构，并保持侧栏抽屉事件。内置浏览器在 280、320、390、768 和 1280 视口验证了 Phoenix 无横向溢出，顶栏上下文不换行，内容区随视口拉伸；窄屏侧边抽屉可以打开，选择导航后自动收起。当前可见 LiveView 菜单为 14 项，包含统一打开 `/api/swagger` 的“接口文档”；`/dashboard` 和旧任务日志状态保留为兼容路径或内部分支，不作为侧栏菜单。LiveView 另已修复配置删除、通知类型筛选、任务筛选提交、字典切换分页、任务编码筛选和新建弹窗取消按钮，提交分别为 `205fd85`、`b59a3fa`、`eba134a`、`15b782b`、`e7ac3d2`、`8d22f85`、`3752575`。Native admin-web 已完成同样的真实浏览器宽度矩阵，两个后端均保留逐页写操作、筛选、导出、批量操作、空态、错误反馈和模态框结果验收项。
- 菜单权限专项已完成：Native、Phoenix 和 admin-web 均支持多级菜单树、父级选择防环、停用/未绑定节点的管理读取、菜单角色绑定查询和替换。Native 菜单更新支持父级重排，并拒绝不存在的父级、自身引用和后代环引用。Phoenix LiveView 角色编辑提供按层级缩进的 `menuIds[]` 多选树，菜单编辑弹窗也提供启用角色复选框和绑定替换；菜单筛选保留匹配节点的祖先。admin-web 菜单表单提供同样的父级防环、启用角色选择和多级筛选祖先保留。对应提交为 Phoenix `86a9114`、`763feb7`、`eb847a7`、`9fb9d33`，Native `4198d1c`、`44cb524`、`8c06179`，admin-web `efb9133`、`65413f4`、`734279d`、`c38d343`。
- admin-web 组织结构筛选也已按多级树规则递归保留完整祖先链，并用异常环保护避免筛选死循环；对应提交为 `6b75eba`。
- 监控页按 Vercel Dashboard 的信息密度重新打磨：状态栏、健康摘要、主证据图表、资源卡片、在线会话和节点详情保持统一层级。admin-web 趋势图增加 80% 关注阈值和数据来源，空趋势显示“暂无采样数据”；Phoenix 当前采样图使用同样的阈值、来源和空态语义，缺失指标显示 `—`，不再显示为 `0%`。监控帮助交互对应 admin-web `379d7f8`、Phoenix `c4f39bd`；admin-web 当前测试为 17 个文件、79 项通过；Phoenix `mix test --include integration` 为 402 项通过，Native 和 Phoenix 真实窗口均已在 280、320、390、768 和 1280 视口检查横向溢出。
- Phoenix 监控页趋势区域已按 admin-web 的 30 分钟采样结构重实现，支持 CPU/内存折线、80% 阈值、坐标轴和采样时间；Phoenix 当前 API 没有历史采样、网络流量、Reductions 和 Erlang 进程/ETS 指标时显示 `—`，不伪造数据。组件测试 8 项通过，对应提交为 `854caca`。
- Phoenix 登录 MFA 表单已使用 admin-web 的状态提示、图标输入框、统一按钮和错误反馈；个人资料页移除头像文件上传块，性别值与 admin-web 统一为空值未知、`1` 男、`0` 女，头像地址仍可保存。对应提交为 `c04db24`，相关集成测试 9 项通过。
- Phoenix 登录页已补齐 admin-web 的窄视口规则：表单和卡片使用父级可收缩宽度，400px 以下缩小内边距和标题字号，900px 以下切换单列；真实 Chrome 在 390、768、1280 宽度确认无横向溢出，登录按钮只显示“登录”。对应提交为 `b6b12ac`。

本次验收仍有明确限制：监控页的部分指标由 Native 接口未提供，页面应显示后端来源和未提供指标；页面通过不表示缺失指标已经补齐。Native 和 Phoenix 已完成真实读取、导航、响应式宽度、筛选空态、新增弹窗打开/关闭、主要 Excel 导出和部分新增/删除检查；Phoenix 和 Native admin-web 均已完成真实 TOTP 登录挑战并进入监控页。Native 还完成了 API Key 敏感操作的真实 step-up 验证；临时用户、令牌、会话和 MFA 挑战已清理，数据库残留计数为 0。菜单权限的 HTTP、组件和 LiveView 回归测试已完成；用户、岗位、任务和审计列表分页也已完成代码与组件验证，Phoenix 用户页、任务页、执行日志页、登录日志和操作审计默认每页 20 条与 admin-web 一致，对应提交为 `dcfaba5`、`2594151`、`1ac38b7`。本轮新增的通知列表详情、当前会话直达和 409 强制登录流程已经完成代码与测试验证，但尚未在真实浏览器窗口中补齐双后端矩阵；其余页面仍需补充逐页编辑、加载状态、错误反馈、分页和批量写操作的完整发布窗口记录。OIDC、公钥硬件 Passkey、CSRF/Cookie、多节点和生产代理链不属于本地窗口验收，不能据此判定通过。
