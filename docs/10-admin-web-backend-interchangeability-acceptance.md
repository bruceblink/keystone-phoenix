# admin-web 后端可替换发布验收矩阵

## 术语和命名

| 术语 | English | 职责和边界 |
| --- | --- | --- |
| admin-web | Admin Web | React 管理页面。本文以正式构建产物作为唯一页面基准。 |
| Native 后端 | Keystone Native | Java/Quarkus HTTP 服务。提供 `/api/v1` 接口。 |
| Phoenix 后端 | Keystone Phoenix | Elixir/Phoenix HTTP 服务。提供与 Native 相同的 `/api/v1` 接口。 |
| 可替换后端 | backend interchangeability | 同一份 admin-web 构建在不修改页面代码的条件下，分别连接两个后端并完成相同验收流程。 |
| 真实窗口验收 | real-window acceptance | 使用 Codex 内置浏览器操作实际页面。Mock 数据、静态 HTML 和组件测试不属于真实窗口通过证据。 |

## 发布目标

正式发布的同一份 admin-web 构建必须满足以下条件：

1. `VITE_ENABLE_MOCK=false` 时，页面只使用当前后端的真实响应。
2. 页面只依赖 `/api/v1` 约定，不读取 Native 或 Phoenix 的内部字段。
3. Native 和 Phoenix 返回相同的响应信封、字段含义、状态码、分页规则、错误分类和 AAL2 行为。
4. 登录、刷新、注销、会话失效、用户、角色、组织、岗位、菜单、API Key、审计、任务、配置、字典、公告、监控和个人资料流程在两个后端完成相同的页面验收。
5. 旧接口和重复接口不再出现在正式路由集合中。

登录会话处理规则：当前浏览器已有有效会话时，登录页直接进入监控页；后端发现其他位置存在活动会话时返回 `409`，页面显示“取消登录”或“强制登录”；强制选项继续传递到密码登录和 MFA 校验请求。MFA 校验阶段再次返回 `409` 时，页面保留当前验证码并复用同一挑战执行强制接管。

本地切换方式：

```bash
# Native
VITE_API_PROXY_TARGET=http://localhost:8080 VITE_ENABLE_MOCK=false pnpm dev

# Phoenix
VITE_API_PROXY_TARGET=http://localhost:4000 VITE_ENABLE_MOCK=false pnpm dev
```

生产部署使用同源 `/api/v1`，不依赖 Vite 开发代理。

## 接口验收条件

| 接口范围 | 必须一致的内容 | 当前证据 |
| --- | --- | --- |
| 认证和会话 | `accessToken`、`refreshToken`、`sessionId`、`clientId`、401、刷新失效和注销 | Native/Phoenix HTTP 契约测试；需对两个后端分别执行真实窗口流程 |
| MFA 登录和 step-up | 401 二次认证请求结构、AAL2 短时令牌、策略要求或 `enforce=true` 时拒绝 AAL1 | Phoenix `a5d5320` 已按 `mfa_required` 对齐普通敏感写，并对用户导入和 Passkey 注册使用 `enforce=true`；Phoenix 和 Native admin-web 均已完成真实 TOTP 登录挑战，Native API Key 敏感操作的真实 step-up 也已通过 |
| 列表查询 | 字段名称、分页 `items/page/size/total`、筛选参数、空结果 | Native/Phoenix 控制器契约测试；需用同一 admin-web 页面双后端核验 |
| 写操作 | 请求字段、201/200/204、`deleted`/`triggered` 结果、验证错误 | Native/Phoenix HTTP 回归；需覆盖发布版本构建 |
| 错误处理 | `success/data/message/error`、401/403/404/422/503 分类 | admin-web 仅对网络错误允许开发 Mock 回退；HTTP 错误必须显示 |
| 路由集合 | 方法与路径集合相同，无重复和过时入口 | `/api/v1` 共 108 条接口（含 health），标准 JWK Set 另计 1 条；集合核对已通过 |

## 页面验收条件

对每个后端重复以下流程。页面、操作顺序和筛选条件保持一致，结果分别记录：

- 登录、刷新页面、注销和会话失效返回登录页。
- 监控页读取真实状态，显示后端来源和未提供指标；空在线会话显示明确空态。
- 用户页使用用户名和展示名筛选，打开新增/编辑，验证 enabled、角色、数据范围错误反馈。
- 角色、部门、岗位、菜单页验证筛选、层级、状态、删除确认和错误反馈；菜单页还必须验证多级树、父级防环、停用节点管理读取和角色绑定。
- API Key 页验证元数据列表、签发一次性密钥、轮换、撤销和 AAL2 step-up。
- 审计页验证用户、动作、资源筛选、分页和导出；页面保持只读交互。
- 任务页验证筛选、编辑、启停、执行、日志和批量删除。
- 配置、字典、公告页验证筛选、CRUD、启用状态、公告发布/取消发布和空态。
- 个人资料页验证资料保存、密码更新的 AAL2 step-up 和会话失效提示。

个人资料密码更新的请求体统一为 `{"password": "..."}`。Native 和 Phoenix 都在 AAL2 step-up 通过后更新密码并撤销当前会话，LiveView 表单与 admin-web 均只要求填写新密码。

Phoenix MFA parity 提交为 `a5d5320`：普通敏感写操作按账号的 `mfa_required` 策略检查 step-up，用户导入和 Passkey 注册使用 `enforce=true`，始终要求 AAL2 step-up。

Phoenix LiveView 管理页面同时以 admin-web 的颜色、布局、筛选栏、表格、卡片、徽标、空态、错误反馈、分页和模态框为视觉基准。Phoenix 静态资源后置加载 admin-web 基准样式，并通过兼容样式保留 LiveView 事件和认证状态。LiveView 重实现不改变 `/api/v1` 接口约定。

2026-11-15 的验收使用同一份 admin-web 构建并设置 `VITE_ENABLE_MOCK=false`。Phoenix 和 Native
均已完成真实浏览器登录、侧栏导航、通知公告页面入口、用户图形个人资料入口和页面读取。新通知铃铛的站内列表/详情、活动会话 409、MFA 继续、注销和强制接管已通过 Chrome CDP 页面验收；Codex 内置浏览器已优先打开，但当前会话不能保持交互，因此不声称可视窗口通过。Native 监控接口返回
`PARTIAL`，Phoenix 监控页返回 BEAM/OTP 运行时数据；两端都显示后端来源和缺失指标状态。Native
和 Phoenix 均在 280、320、390、768 和 1280 视口完成宽度检查，未发现横向溢出。Native
admin-web 已完成用户新增和删除真实窗口流程：创建唯一测试用户时先显示密码策略错误，再使用合规密码成功创建；
列表刷新后选择该用户、确认删除并完成测试数据清理。Phoenix API 通过同一 admin-web 在端口 5176、使用
`admin/123456` 登录后完成对应的用户新增、列表刷新、选择、删除确认和清理。除已记录的筛选、弹窗、导出和批量确认外，
两端仍未完成逐页写操作、加载状态、错误反馈、分页、编辑和批量操作结果的完整发布矩阵。

Phoenix 补充窗口记录使用 `VITE_API_PROXY_TARGET=http://127.0.0.1:4000` 和前端端口 `5176`。
同一份 admin-web 使用 `ag1/123456` 登录成功，13 个可见菜单页面、通知公告入口、顶栏用户图形入口、
监控帮助展开和关闭均通过验收，并在 280、320、390、768 和 1280 视口完成宽度矩阵检查。

Native 和 Phoenix 的同一份 admin-web 还完成了角色、组织、岗位、菜单、API Key、操作审计、登录日志、
系统配置和字典页面的无结果筛选与重置；用户、角色、组织、岗位、菜单、系统配置、字典、通知和定时任务的
新增弹窗均能打开并取消关闭。两端的空态、查询和模态框关闭结果一致。

菜单权限接口已完成替换验收：`GET /menus` 对 `menu:manage` 返回完整未删除树，对普通 `menu:read` 返回已启用且已绑定树；`GET/PUT /menus/:id/roles` 均返回或接收 `{roleCodes}`。缺失、空值、非数组、未知角色和停用角色均返回 422 `validation_failed`，空数组用于清除绑定。Native、admin-web 和 LiveView 均提供多级菜单父级选择、角色绑定和父级防环；Native 更新还支持父级重排并拒绝不存在父级、自身引用和后代环引用。

用户、角色、岗位、操作审计和登录日志页面的“导出 Excel”在 Native 和 Phoenix 均通过真实窗口检查。
Phoenix 角色导出的 `406` 已在 `220fdde` 修复，API 管道现在接受 XLSX MIME。

Native 和 Phoenix 的角色页、Native 任务页还完成了选择记录、打开批量删除确认并取消的真实窗口检查，未执行删除。

Native 和 Phoenix 的角色、组织、岗位页面均完成真实新增、列表显示、删除确认和测试数据清理。Phoenix 未登记菜单权限的错误已从 500 修复为 422 `validation_failed`（`55e92fe`）；API Key 缺失和重复轮换状态保持 Native 的 404/409，并返回相同的 `resource_not_found`/`resource_conflict` 业务码，对应本次错误码对齐提交。

任务手动触发接口在两个后端都返回 HTTP 200 和 `data.triggered=true`，表示请求已接受；并发锁导致的跳过结果写入执行日志，页面通过日志查看最终状态。Phoenix 已增加并发锁 HTTP 契约测试，与 Native/admin-web 的结果字段保持一致。

Phoenix LiveView 已完成共享壳、登录、账号、组织、系统和任务页面的主要视觉重实现。侧栏、顶栏、
颜色令牌、卡片、筛选区、按钮、表格、徽标、状态 footer、用户图形个人资料入口和侧栏菜单结构已经按 admin-web
对齐。Phoenix 壳 DOM 已使用 `app-shell`、`sidebar`、`shell-content`、`topbar` 和 `shell-main` 原生结构，兼容样式只处理 LiveView 的导航和认证差异。窄屏布局使用流式宽度，
没有设置固定页面最小宽度；内置浏览器在 280、320、390、768 和 1280 视口验证了 Native admin-web 和 Phoenix 页面没有横向溢出。
Phoenix 和 admin-web 可见菜单均为 14 项，包含统一打开 `/api/swagger` 的“接口文档”，并已移除“工作台”、个人资料菜单和“系统”分组标题；`/dashboard` 仍保留为兼容深链接。发布前仍需逐页补全导出、批量操作、加载状态、错误反馈、分页、编辑和写操作结果。

监控帮助按钮已在两个前端实现展开和关闭，显示系统 API、缺失指标和 `PARTIAL` 状态的阅读说明。侧栏仅保留“运维审计”分组标题；系统配置、字典管理和通知公告直接列在其后，两个前端的菜单结构一致。

监控页的状态栏、资源卡片、在线会话、节点详情、80% 关注阈值、系统 API 来源和无采样空态已按 admin-web 组件层级重实现。Phoenix 缺失资源字段统一显示 `—`，不会把缺失值误读为 `0%`。Phoenix 监控页、任务页、组织页和系统页分别在提交 `f4c4e7b`、`65d0cd2` 和 `9431783` 中完成页面模板重实现；admin-web 初始响应式修复在 `661fb2a`，当前中等窄视口和登录页最终修复在 `3e01da7`，Phoenix 壳结构、抽屉和响应式断点分别在 `7f86d43`、`21a0ce2` 和 `953a8fb` 推送，角色旧接口清理在 `84d8988` 推送，工作台入口移除在 `0d34206` 推送，通知发布错误反馈在 `193ec91` 推送，监控帮助和侧栏分组对齐分别在 `379d7f8` 和 `80031cc` 推送，Phoenix 监控帮助状态修复在 `c4f39bd` 推送，Phoenix MFA parity 在 `a5d5320` 推送，两个前端删除“系统”分组标题分别在 `13bcfeb` 和 `65ac3cf` 推送。LiveView 配置删除、通知类型筛选、字典切换分页、任务编码筛选和新建弹窗取消按钮分别在 `205fd85`、`15b782b`、`e7ac3d2`、`8d22f85`、`3752575` 推送。

2026-11-15 登录页视觉复核使用同一内置浏览器视口分别打开 admin-web 和 Phoenix 代理页面。Phoenix 真实窗口使用 `http://127.0.0.1:5176/login`、Phoenix `4000` 后端和 `VITE_API_PROXY_TARGET=http://127.0.0.1:4000`；390x900 为单列 350px 内容宽度，768x900 为单列 560px，1280x900 为 1050px 双列。三档 document/body scrollWidth 均等于视口宽度，关键标题、输入框、按钮和脚注均在视口内，按钮只显示“登录”。Phoenix 对应提交为 `b6b12ac`，admin-web 对应提交为 `3e01da7`。

admin-web 响应式壳已补齐中等窄视口断点：侧栏在 390 和 768 视口切换为抽屉，监控区域切换为单列；1280 视口保留桌面双列。登录页在 390、768、1280 视口分别使用单列、单列和双列布局。真实 Chrome 验证三种宽度的 document/body 均等于视口且无横向溢出，对应提交为 admin-web `3e01da7`。

Phoenix 监控页趋势区域已按 admin-web 的 30 分钟采样结构重实现，支持 CPU/内存折线、80% 阈值、坐标轴和采样时间；Phoenix 当前 API 没有历史采样、网络流量、Reductions 和 Erlang 进程/ETS 指标时显示 `—`，不伪造数据。组件测试 8 项通过，对应提交为 `854caca`。Phoenix 登录 MFA 表单已使用 admin-web 的状态提示、图标输入框、统一按钮和错误反馈；个人资料页移除头像文件上传块，性别值与 admin-web 统一为空值未知、`1` 男、`0` 女，头像地址仍可保存。对应提交为 `c04db24`，相关集成测试 9 项通过。

Phoenix 审计页已按 admin-web 的只读约定移除删除按钮和操作列，保留后端事件兼容已有调用；对应提交为 `ace60dd`。Phoenix 个人资料页已按 admin-web 改为只填写新密码，密码更新接口统一使用单个 `password` 字段，并在 AAL2 通过后撤销当前会话；对应提交为 `b4c92cb`。重启当前 Phoenix 服务后，内置浏览器确认个人资料页只渲染 `input[name="password"]`，不再渲染 `oldPassword` 或 `newPassword`。

Phoenix 任务页已补齐与 admin-web 一致的当前页勾选、全选、批量删除确认、删除反馈和筛选后选择状态清理；对应提交为 `4ac1dc7`。原有单项编辑、启停、执行、取消和权限检查保持不变。岗位页已按 admin-web 的每页 20 条规则补齐分页、筛选后回到第 1 页，以及新增、编辑、启停和删除后的分页重置；对应提交为 `f3e8363`。admin-web 任务列表已按相同的每页 20 条规则补齐分页，并限制当前页全选范围；对应提交为 `eca3a86`。Phoenix 用户页默认分页大小已调整为 20，与 admin-web 一致；对应提交为 `dcfaba5`。Phoenix 任务列表和执行日志默认分页大小也已调整为 20；对应提交为 `2594151`。Phoenix 登录日志和操作审计默认分页大小已调整为 20，与 admin-web 一致；对应提交为 `1ac38b7`。

Phoenix 角色页已对齐 admin-web 的当前结果集选择：支持当前筛选结果全选、单项取消、显示选中数量，并在刷新、筛选、保存、状态更新和删除后清空选择；对应提交为 `41a9517`。真实窗口已验证 1280 和 390 视口、全选/取消一项、无结果筛选后的“删除角色（0）”状态。

Phoenix 通知公告页已对齐 admin-web 的当前结果集选择和批量删除确认，沿用既有领域删除函数，不新增接口；刷新、筛选、重置、保存、状态更新、发布和删除后都会清空选择。对应提交为 `4588322`，集成测试覆盖全选数量、单项删除和其他公告保留。

真实窗口已使用同一份 admin-web 连接 Phoenix 验证通知公告页：全选两条记录、无结果筛选后的空态和“删除公告（0）”状态均通过；1280 和 390 视口没有横向溢出。

Phoenix 字典页的未选择类型状态已与 admin-web 对齐：显示“字典条目”“选择类型后查看条目。”“选择类型后维护”和“选择一个字典类型”；选择类型后保留条目表格和分页。字典类型筛选同时匹配名称和编码，无匹配时清空条目选择并显示左右两侧空态。对应提交为 `39c74c5`、`1c4b108`，组件和集成测试覆盖正常空态、筛选空态和字典数据弹窗兼容。

Phoenix LiveView 真实窗口复核补充了字典页：输入无匹配类型后，左侧显示“没有匹配的字典类型”，右侧显示“选择一个字典类型”和“选择类型后维护”；1280 和 390 视口的文档宽度均与视口一致。多级菜单页同时显示了按层级缩进的菜单目录。

任务页已按 admin-web 对齐暂停任务的交互：停用任务的“执行”按钮带 `disabled`，LiveView 事件也返回错误反馈。为保持 Native/Phoenix 后端可替换，两个 `/jobs/{id}/trigger` HTTP 接口继续保留既有直接触发约定，不因页面禁用改变后端接口语义。Phoenix 对应提交为 `da6a27a`、`735eb7e`，Native 全量测试 `222` 项通过。

本次真实窗口复核创建临时暂停任务后验证了 Phoenix 任务页：1280 和 390 视口下暂停任务行的“执行”按钮均为禁用状态，文档宽度与视口一致；临时任务、会话和浏览器进程已清理。

Phoenix 通知页已补齐 `notice_filter` 和 `selected_notice_ids` 到 LiveView 组件的赋值，筛选和批量选择状态不再被默认赋值覆盖，对应提交为 `3a2efab`。真实窗口输入无匹配标题后显示“没有匹配的公告”，不渲染空表头。

Phoenix LiveView 已将用户、部门、岗位、角色、菜单、配置和任务页面的筛选、选择及当前详情状态显式传给组件；筛选输入和批量操作状态不会在事件后回退到默认值。用户筛选值和删除按钮状态由集成测试验证，对应提交为 `fa66fff`。

Phoenix 菜单页已按 admin-web 基准展开任意层级菜单树，兼容 `nil`、`0`、`"0"` 和混合类型父级 ID；深层筛选保留祖先节点，表格使用响应式层级缩进，并在编辑父级选择中排除自身和后代。对应提交为 `763feb7`。

本次内置浏览器复核使用真实 Phoenix 服务和 `ag1/123456`：菜单筛选 `user:read` 显示“系统管理”根节点和“用户管理”子节点，用户筛选 `ag1` 保留输入值并在选择后显示“删除用户（1）”；1280 视口的文档宽度为 1280，390 窄屏的文档和 body 宽度均为 390，侧栏抽屉可以打开且页面没有横向溢出。菜单表格在窄屏内部滚动，不扩大页面宽度。

Phoenix 菜单编辑弹窗已补齐 admin-web 的“可访问角色”复选框，只展示启用角色；编辑时读取现有绑定，保存时替换绑定，空选择会清除绑定。LiveView 集成测试覆盖读取、保存、重新打开和清空，对应提交为 `86a9114`。真实窗口已确认角色复选框和当前选中状态可见。

Phoenix 菜单 LiveView 现在兼容 Native 的 `enabled` 布尔字段和 `MENU`、`BUTTON`、`DIRECTORY` 字符串类型，同时保留 Phoenix 的 `status` 和整数类型映射；菜单状态与类型展示已补充组件和数据测试，随提交 `c04db24` 验证。

Native/admin-web 真实窗口复核补充了登录加载状态、错误密码反馈、用户筛选和批量选择、角色编辑取消、菜单多级筛选祖先保留，以及 390 窄屏文档/body 宽度检查。Native 使用 MySQL 8.4 和端口 8080；admin-web 代理目标必须显式使用 `http://127.0.0.1:8080`，否则登录请求会返回 502。

Native 菜单树读取已补充 `menu:read` 权限检查；无该权限的已认证主体访问 `GET /v1/menus` 返回 `403 permission_denied`，对应提交为 Native `ef129ea`。Phoenix 个人资料读取、更新、头像和密码更新已分别要求 `user:read`、`user:update`、`user:update` 和 `user:reset-password`，对应提交为 `4ea659f`，并补充受限主体 HTTP 回归。

Native 已删除 Phoenix 和 admin-web 都不使用的 `DELETE /v1/login-logs?ids=...` 与 `DELETE /v1/operation-logs?ids=...`，同步删除旧权限目录项并增加 `V57__remove_audit_log_delete_permissions.sql`；admin-web 继续使用读取和导出接口。对应提交为 Native `a7e33bb`，定向权限测试和全量 `./gradlew test --no-daemon` 均通过。

Phoenix 已删除岗位更新控制器中无法由现行路由触发的 `postId` 参数分支，并将权限测试迁移到 Native/admin-web 使用的规范字段；对应提交为 `a2a6ea4`，定向测试 9 项通过。Phoenix 和 Native 现仅保留 admin-web 使用的批量参数：用户/角色 `ids`、公告 `notice_ids`、任务 `jobIds`；旧别名返回 422 `validation_failed`。对应提交为 Phoenix `592ceb5`、Native `591ac88`。Phoenix 角色成员接口另已删除 `user_ids`、`roleId`/`:role_id` 兼容字段和旧分页响应，统一使用 `userIds` 和用户 ID 数组，对应提交为 `84d8988`。任务列表、用户列表和任务日志也已删除旧 `{rows,total}`/`rows` 响应字段，统一使用 Native 的数组和 `items` 结构，对应提交为 `fde3b9e`。

Phoenix 角色成员分配和移除现在与 Native 一样统一使用 `role:assign`；之前控制器传入的 `role:update` 已删除，角色范围集成测试在只授予 `role:assign` 时通过。对应提交为 `c45871a`。

Phoenix LiveView 角色页面的用户分配和移除事件也已改为检查并传递 `role:assign`，与 HTTP 接口和 Native 权限边界一致；LiveView 管理集成测试通过，对应提交为 `5e5c759`。

Phoenix 角色控制器的 `unassign_users` 权限声明也已统一为 `role:assign`，避免内部动作声明和 Native/HTTP 权限边界不一致；角色权限回归测试通过，对应提交为 `bfda55e`。

主线继续收口：admin-web `0f66cd3` 新增角色成员入口，调用统一的 `GET/PUT/DELETE /roles/:id/users`，支持已分配/可分配列表、分页、MFA step-up、刷新、重试和错误反馈；角色成员 API 客户端与 Native/Phoenix 的用户 ID 数组响应一致。Phoenix `85e9d7e` 修复角色成员撤销忽略 URL `role_id` 的问题，只有用户当前属于目标角色时才清除绑定，并补充跨角色回归；Phoenix `b460ad3` 将注销接口权限与 Native 对齐为 `session:revoke`，补充无权限 403 和有权限成功回归。

多角色数据语义的替换阻塞已关闭：Phoenix 已通过 `sys_user_role` 关联表支持多角色用户，用户写入、角色成员分配、鉴权、菜单、数据范围和认证响应已完成对应切片。角色成员读取按目标角色关联判断，并对齐缺失角色的 `404 resource_not_found` 和空 `userIds` 操作结果。Native/Phoenix 继续使用双方已有的用户 ID 数组接口；统一用户详情和服务端分页 DTO 属于后续页面体验增强，不再是后端替换前置条件。

## 发布前证据

每个正式版本必须保留以下证据：

1. Native 和 Phoenix 各自的完整测试、严格编译和源码行数结果。
2. 同一 admin-web commit 的 `pnpm test:run`、`pnpm typecheck` 和 `pnpm build`。
3. `VITE_ENABLE_MOCK=false` 下分别连接 Native、Phoenix 的真实窗口截图或操作记录。
4. 两个后端的路由集合差异、旧接口搜索和数据库迁移状态。
5. 未完成的 OIDC、公钥硬件 Passkey、CSRF/Cookie、多节点和生产代理检查必须单独标记为证据缺口，不能写成页面通过。

API Key scope 现在通过两端统一的 `GET /api/v1/permissions/catalog` 动态目录逐项选择。目录读取要求 `api-key:create`，返回 `allowed` 标记，前端只显示当前主体可授予的权限，并在提交前阻止越权 scope。对应提交为 Native `884a9cb`、`2376eb0`、Phoenix `50e1828`、`80e0f39`、`0a8a547`、Phoenix LiveView `7a8e16f`、`380aa63` 和 admin-web `090dc21`。真实 Chrome 已验证 Phoenix 后端的动态目录加载、搜索和单项选择。

当前状态：后端业务路由集合、DTO 适配和 Native/Phoenix HTTP 接口对齐已完成；旧接口和重复接口已从正式业务路由集合删除；同一份 admin-web 已在 `VITE_ENABLE_MOCK=false` 下分别连接 Native 和 Phoenix，两个后端均完成真实浏览器登录、导航、个人资料入口和 280、320、390、768、1280 宽度检查。Native 和 Phoenix 的用户新增、列表刷新、选择、删除确认和测试数据清理已完成真实窗口验收；两端还完成了 9 个列表页的无结果筛选与重置、9 类新增弹窗的打开和取消关闭、用户/角色/岗位/操作审计/登录日志的 Excel 导出、角色/组织/岗位新增删除和角色页批量删除确认的取消检查。菜单权限的多级树、角色绑定和后端边界已由 Native HTTP、Phoenix HTTP、Phoenix LiveView 和 admin-web 测试覆盖。Phoenix 和 Native admin-web 已完成真实 TOTP 登录挑战，Native API Key 敏感操作的真实 step-up 也已通过。用户可见后端来源和错误文案已泛化为系统 API。Phoenix LiveView 已增加 admin-web 对齐的深链接、页面模板和响应式壳；通知列表/详情、当前会话直达 dashboard、409 活动会话确认、MFA 继续、强制登录和注销已通过 Chrome CDP 页面验收。其他批量操作、加载状态、错误反馈、分页、编辑和逐页写操作矩阵以及 OIDC、硬件 Passkey、CSRF/Cookie、多节点和生产代理链仍是发布证据缺口。
2026-11-16 增量：Phoenix `84b7b8e` 已关闭四类空结果空表头问题；admin-web `2c79ff7`、`00a72af` 已补充六个页面的旧数据刷新失败反馈和重试入口。LiveView 事件层的统一业务错误码仍需独立切片。

2026-11-16 错误码和查询状态增量：Phoenix `27fd9bd`、`c6bebb9`、Native `f282c99`、`27b969d` 和 admin-web `adc3db0` 已补齐错误码精确反查。调用方可以从稳定的业务错误码取得业务含义和排错元数据；HTTP 状态、响应字段和未知代码的兼容处理保持原约定。三端静态目录检查通过，包含 21 个跨项目服务端错误码和 4 个 admin-web 客户端本地错误码。该结果不替代逐页面的真实错误反馈验收。

admin-web `4ccc35d` 已为 Users、Jobs、LoginLogs、OperationsAudit 保存筛选、分页和任务详情状态到命名 URL 参数，并通过前端测试、类型检查和构建。Native 与 Phoenix 后端替换验收仍需补充其余页面的 URL 状态、加载失败、编辑、批量写入和详情返回矩阵；当前不能把四个页面的状态恢复结果扩展为全站通过。

2026-11-16 第二批闭环证据：同一份 admin-web 连接 Phoenix 时，用户、任务、任务日志、字典类型、字典条目和公告的 LiveView 读取失败会保留旧数据并显示可重试错误；admin-web 连接 Native 或 Phoenix 时，公告和字典页面的刷新失败也保留旧数据，诊断区域显示错误码、业务含义和请求标识。对应提交为 Phoenix `b45e40d`、`4cbfcdf`，admin-web `e1fc667`、`8b302f0`、`d090f13`、`db884f3`。该批次通过三端全量测试和构建，但尚未完成其余页面的逐页真实编辑、分页、批量写入和详情返回矩阵。

第三批闭环证据：admin-web 的菜单、角色和组织页面在已有数据刷新失败时保留旧内容并提供错误码诊断和重试；Phoenix LiveView 岗位页保留旧列表和筛选条件并提供稳定错误码反馈。对应提交为 admin-web `c79a1b0`、`acee1c3` 和 Phoenix `61617bf`。该批次继续保持相同的后端接口和 HTTP 状态，剩余页面矩阵仍需逐页补齐。

第四批闭环证据：admin-web `3d28cee` 将初次读取错误面板统一为安全提示、业务错误码、业务含义、请求标识和重试入口；`2df33b3` 将 API Key 写操作与删除确认接入同一诊断组件。Phoenix `339d2b6` 将登录日志和操作审计的刷新、筛选失败改为保留旧数据和筛选条件。`b365483` 已验证 admin-web 的 74 条接口调用全部存在于两个后端，两个后端接口集合保持一致。该批次最新全量回归为 Phoenix `425 passed`、admin-web `23 files / 118 tests passed`、Native 测试和构建成功，但监控、系统配置及其他未覆盖 LiveView 读取事件仍需继续验收。

第五批闭环证据：Phoenix `06b4708`、`9245e78` 将监控快照、系统配置刷新和保存后的重新读取接入统一错误反馈，并保持源文件行数限制；admin-web `e0d84f6` 将角色和组织筛选状态写入命名 URL 参数，刷新和角色前进/后退可恢复。定向测试均通过；Native/Phoenix HTTP 接口未改变。其余页面矩阵和真实窗口证据仍需继续补齐。

第六批闭环证据：admin-web `720f301` 将配置、公告、字典表单和角色导出失败统一显示安全提示、业务错误码、业务含义和请求标识，未改变后端接口。全量前端回归为 `23 files / 116 tests passed`；其他表单、导出和真实窗口结果仍需继续补齐。

第七批闭环证据：admin-web `bd14dde` 将用户/角色写操作、用户导出和角色删除失败接入统一诊断；Phoenix `a8489cb` 将组织、岗位、角色和菜单缺失反馈映射为稳定的 `resource_not_found`。admin-web 全量回归为 `23 files / 118 tests passed`；其余写操作和真实窗口证据仍需继续补齐。

第八批证据：Phoenix `4bdcf12`、`5709a50` 和 `cef74fc` 补齐剩余 LiveView 事件的稳定业务错误码，覆盖用户导入、任务执行/取消、字典与公告、登录任务回调、个人资料、API Key、配置、审计/组织导出和在线会话。原有中文提示、HTTP 状态、接口字段和权限边界保持不变。Phoenix 集成测试为 `432 passed`，admin-web 为 `23 files / 121 tests passed`，类型检查和生产构建通过；Native 测试和生产构建成功。三端错误码目录仍为 21 个服务端代码和 4 个客户端本地代码，路由集合检查仍为 admin-web 74 条调用、Native/Phoenix 各 108 条 `/api/v1` 路由。

该批次完成了代码级错误反馈闭环，但不替代逐页面真实错误反馈、加载状态、编辑、批量写入和详情返回的发布矩阵。Codex 内置浏览器已按优先顺序打开，但当前会话无法保持交互，因此本轮未新增可视窗口通过证据；既有 Chrome CDP/headless 证据仍按其边界记录。OIDC、公钥硬件 Passkey、CSRF/Cookie、多节点和生产代理链仍未完成正式验收。

第九批证据：Phoenix `3a359f0` 修复组织页面和 API Key 页面将刷新或写入后读取失败吞成空列表的问题。部门、岗位、角色、菜单、角色成员和 API Key 的读取结果现在区分成功、空结果和服务失败；失败时保留旧数据并显示稳定错误码。Phoenix 集成测试为 `433 passed`。账号页兼容加载调用、分页覆盖和逐页面真实操作矩阵仍需继续补齐。

第十批证据：admin-web `4cc82f6` 将 Configs、Dictionaries、Notices、Profile、LoginLogs 和 OperationsAudit 的删除、发布、保存和导出失败统一接入 `ActionError`；错误面板显示安全业务文案、业务错误码、业务含义和 `requestId`，删除确认保留完整错误对象。admin-web 全量回归为 `24 files / 127 tests passed`，类型检查和构建通过；Phoenix 最新集成回归为 `434 passed`。该批次完成代码级操作错误诊断，但分页覆盖、账号页剩余入口和逐页面真实浏览器矩阵仍未完成。

分页审计结论：当前 Phoenix 多数分页是全量读取后的内存切片，admin-web 也有多个全量列表页面。该实现暂时保持筛选和页面行为，但不能作为大数据量服务端分页验收证据。下一阶段按 Users/Jobs/Posts/Configs/Notices/Dictionary items/Logs、Roles、树结构 Departments/Menus、API Keys 分批改造，并要求 Native/Phoenix/admin-web 同时验证查询参数、`total`、筛选语义、页码复位和失败旧页保留。

### 2026-11-16 配置与 API Key 服务端分页增量

本轮完成两个列表资源的三端分页闭环。配置列表提交为 Native `a9d0f97`、Phoenix `2fba076`、admin-web `1360c7a`，API Key 列表提交为 Native `d5e6540`、Phoenix `5576d95`/`2ee3b59`、admin-web `4f9152e`。请求带 `page`/`size` 时统一返回 `{items,page,size,total}`；省略分页参数时继续返回旧数组，保证尚未迁移的调用方兼容。配置支持 `keyword`，API Key 支持 `keyword`/`query` 与 `status=all|active|revoked`，权限和数据范围检查保持不变。

Phoenix LiveView 和 admin-web 都保存筛选、页码和总数；筛选、写入、轮换、撤销后回到第 1 页；刷新失败保留上一次成功数据并显示可重试的业务错误反馈。Native 与 Phoenix 的 HTTP 控制器均覆盖分页、筛选和旧数组兼容测试。

验证结果：Phoenix 全量测试 `382 passed, 53 excluded`，API Key 集成测试 `16 passed`；admin-web 全量测试 `24 files / 133 tests passed`，类型检查和构建通过；Native 全量 Gradle 测试和 `quarkusBuild` 通过。错误码目录检查仍为 21 个服务端代码和 4 个客户端本地代码；路由检查为 admin-web 74 条调用、Native/Phoenix 各 108 条 `/api/v1` 路由，JWK 集合一致。

本轮同时修复 `scripts/check_api_route_contract.py` 对 Native 多行方法声明的识别问题，提交为 Phoenix `968f8de`。GitHub Actions 运行 `43870913581` 的失败原因为 `mix check.source_lines` 将 `admin_support.ex` 识别为 601 行；该文件已随 `5576d95` 压到限制以内，本地 `mix format --check-formatted` 和 `mix check.source_lines` 已通过。修复后的推送运行 `43873433545` 和文档更新运行 `43874290343` 均已通过格式、源码行数、严格编译、单元/数据库测试、覆盖率报告和 LiveView 集成测试。

当前未完成项仍包括其他页面的完整服务端分页和逐页编辑/批量写入/详情返回矩阵，以及 OIDC、公钥硬件 Passkey、CSRF/Cookie、多节点恢复、生产代理链和可视浏览器窗口证据。

### 2026-11-16 公告分页与重复读取路由收口

公告管理列表已完成三端分页闭环：Native `76685eb`、Phoenix `a86783c`、admin-web `d316150`。带 `page`/`size` 时返回 `{items,page,size,total}`，无分页参数时保留旧数组响应；筛选支持关键词、标题/内容、类型、发布状态和启用状态。Phoenix LiveView 与 admin-web 保存筛选和页码，翻页、刷新、写入、发布和删除后回到第一页；刷新失败保留旧页并显示业务错误反馈。

为保持接口检查可反查，admin-web 的 API Key 和公告数组/分页读取已合并到单一客户端路由入口，提交为 `092f472`。静态路由检查重新通过：admin-web 74 条调用，Native/Phoenix 各 108 条 `/api/v1` 路由，JWK 路由一致，无旧路径标识。

本轮验证：Phoenix 默认测试 `382 passed, 54 excluded`，含集成测试 `436 passed`；admin-web 公告分页后 `24 files / 135 tests passed`，类型检查和构建通过；Native 公告分页全量测试和 `quarkusBuild` 通过。CI 修复后的 Phoenix 运行 `43875384260` 已完整通过。

### 2026-11-16 字典条目分页闭环

字典条目列表已完成三端服务端分页：Native `e28e98c`、Phoenix `8a6fe46`、admin-web `a62ded7`。无 `page`/`size` 时保留旧数组响应；带分页参数时返回 `{items,page,size,total}`，默认每页 20 条，服务端上限 100 条。查询继续要求字典类型启用，但保留条目自身的启用状态；Phoenix 和 admin-web 支持关键词筛选。

Phoenix LiveView 和 admin-web 在选择字典类型后使用服务端分页，刷新、选择切换、写入和删除后回到第 1 页；刷新失败保留旧条目并显示错误反馈。Native/Phoenix 保留 `dictionary:read` 权限和数据范围。

验证结果：Phoenix 默认测试 `382 passed, 54 excluded`，集成测试 `436 passed`；admin-web 全量测试 `24 files / 137 tests passed`，类型检查和构建通过；Native 全量测试和 `quarkusBuild` 通过。跨项目错误码、路由集合和源码行数检查继续通过。

下一阶段继续处理登录日志、操作审计和其他尚未完成的逐页面写入、详情返回及真实浏览器矩阵；OIDC、公钥硬件 Passkey、CSRF/Cookie、多节点恢复和生产代理链仍单独保留为发布证据缺口。

### 2026-11-16 LiveView 审计日志分页对齐

Phoenix `b9d8530` 将 admin-web 已使用的登录日志和操作审计分页约定重新实现到 LiveView。LiveView 事件现在携带当前页和筛选条件，页面显示服务端总数，筛选、刷新和翻页失败时保留旧数据并显示错误反馈；导出接口继续使用完整结果集。这样，Native 和 Phoenix 可以继续互换作为同一份 admin-web 的后端，查询参数和返回总数不因前端实现不同而变化。

验证结果：Phoenix `382 passed, 54 excluded`，集成测试 `436 passed`；错误码目录和 API 路由集合检查继续通过。剩余未闭环项仍需按页面补齐编辑、批量写入、详情返回、加载状态和真实窗口验收。

### 2026-11-16 任务列表后端替换对齐

Native `819f5b7`、admin-web `9dfcb1a` 和 Phoenix `6f6776e` 完成任务列表分页对齐。admin-web 发送 `page`、`size` 和 `keyword`，Native 与 Phoenix 返回相同的 `items/page/size/total` 结构；无分页参数的旧数组调用保持兼容。Phoenix LiveView 使用同一服务端分页查询，筛选、翻页、刷新、详情编辑和任务日志读取保持闭环。

验证结果：Phoenix 默认测试 `384 passed, 54 excluded`，集成测试 `438 passed`；admin-web `24 files / 137 tests passed`，类型检查和构建通过；Native 测试和 `quarkusBuild` 通过。剩余页面仍需继续补齐服务端分页、编辑、批量写入、详情返回和真实窗口矩阵。

### 2026-11-16 岗位列表后端替换对齐

Native `cec66b0`、admin-web `de58b4f` 和 Phoenix `6447e0c`/`487fa9e` 完成岗位列表分页对齐。admin-web 发送 `page`、`size`、`keyword` 和状态筛选，Native 与 Phoenix 返回相同的 `items/page/size/total` 结构；Phoenix LiveView 使用同一服务端查询，筛选、翻页和空结果状态保持闭环。

验证结果：Phoenix 默认测试 `385 passed, 54 excluded`，集成测试 `439 passed`；admin-web `24 files / 137 tests passed`，类型检查和构建通过；Native 测试和生产构建通过。角色列表、菜单树和其他页面仍需继续补齐对应的服务端分页及详情矩阵。

### 2026-11-17 角色列表后端替换对齐

Native `5b75636`、admin-web `6756234` 和 Phoenix 本次提交完成角色列表替换对齐。admin-web 发送 `page`、`size`、`keyword` 和状态筛选时，Native 与 Phoenix 返回相同的 `items/page/size/total` 结构；无参数调用保持旧数组响应。Phoenix LiveView 角色列表使用服务端当前页，角色菜单和成员子面板继续读取完整角色目录，避免分页影响权限绑定。

验证结果：Native 角色 HTTP 定向测试、全量测试和构建通过；admin-web `24 files / 140 tests passed`，类型检查和生产构建通过；Phoenix 角色 HTTP 集成测试 10 项、LiveView 组织测试 18 项通过。Phoenix 全量测试、源码行数检查和 CI 在本次提交后继续执行。该结果不替代 Codex 内置浏览器可视窗口验收。

Phoenix `93efb71` 补齐角色列表写入闭环。角色保存、状态变更、批量删除和成员分配成功后，LiveView 会更新完整角色目录、第一页和 `total`；翻页会清空上一页选择，避免跨页误删。重新读取失败时保留旧页并显示稳定错误反馈。该修复不改变 Native/Phoenix HTTP 字段和状态码。

菜单筛选状态已同步：admin-web `b4c6c46` 与 Phoenix `8cd0295` 均把关键词保存到菜单深链接，查询、直接打开和重置行为一致。菜单树继续完整读取，以保持多级父子关系；本轮没有新增或删除菜单接口。

Phoenix `05f148e` 又完成组织结构树的 URL 状态对齐，并将菜单关键词参数修正为 admin-web 使用的 `menus_keyword`。组织结构使用 `departments_keyword`；树接口、父子关系和角色绑定接口未改变。

Phoenix `f7cf392` 修复了测试环境后台清理进程访问 SQL sandbox owner 的 CI 时序问题。生产配置未改变；最新 CI 的默认测试为 `386 passed, 56 excluded`，覆盖率和 LiveView 集成测试均为 `442 passed`。

### 2026-11-17 用户管理和审计深链接增量

Phoenix `bdbad56` 将 LiveView 用户管理改为服务端分页。用户筛选、刷新、翻页和写入后重新读取都携带 `pageNum`、`pageSize`、`username`、`displayName`，页面使用服务端返回的 `rows` 和 `total`；翻页会清空当前页选择，读取或写入后的重新读取失败会保留旧页并显示稳定业务错误。用户编辑、删除、导入和状态变更继续使用原有权限、数据范围和 HTTP 接口。

Phoenix `7f03904` 将登录日志和操作审计的筛选、页码和重置状态写入与 admin-web 一致的命名 URL 参数。直接打开深链接时，LiveView 会恢复筛选和页码；查询、翻页和重置会同步更新 URL。admin-web `b9da92a` 同时修复了非法分页深链接值的回退规则，`0`、负数、小数、`NaN` 和 `Infinity` 不会传给后端。

验证结果：Phoenix `mix test --include integration` 为 `443 passed`，`mix compile --warnings-as-errors`、格式检查、源码行数检查和差异检查通过；用户分页集成和页面组件定向测试通过。admin-web 分页状态定向测试为 `2 passed`，全量测试为 `25 files / 143 tests passed`，类型检查和生产构建通过。

本轮仍不宣称完成真实可视浏览器窗口验收。Codex 内置浏览器在当前会话不能保持交互，现有 Chrome CDP/headless 证据仍按无头边界记录。OIDC、公钥硬件 Passkey、CSRF/Cookie、多节点恢复、生产代理链和其余逐页面编辑、批量写入、详情返回矩阵继续作为未完成发布证据项。

Phoenix `e2231de` 又将用户管理的 `users_username`、`users_displayName` 和 `users_page` 写入深链接；用户页面直接打开、查询、翻页和重置时与 admin-web 的 URL 状态一致。

第十一批闭环证据：Phoenix `238c32d` 完成任务列表与任务日志的命名 URL 状态恢复，使用 `jobs_keyword`、`jobs_jobPage`、`jobs_logPage`、`jobs_selectedJobId`；直接打开深链接会读取选中任务详情和日志，筛选、翻页、刷新、切换任务和重置保持 URL 与页面状态一致。admin-web `e9b7b05` 增加 `GET /jobs/:id`，在选中任务不属于当前列表页时补读详情，避免跨页深链接显示错误空态。admin-web `3b6225e` 将 API Key 权限目录读取失败接入稳定业务错误码、业务含义、请求标识和重试入口。

本批次验证：Phoenix 集成测试 `444 passed`；任务深链接定向测试 `3 passed`；admin-web 全量测试 `25 files / 145 tests passed`，类型检查和生产构建通过；源码行数、差异、错误码和路由契约检查通过。当前 admin-web 使用 73 条 API 调用，Native 与 Phoenix 各提供 108 条 `/api/v1` 路由，路由集合一致，21 个服务端业务错误码和 4 个 admin-web 本地错误码一致。

验收边界：本批次没有新增 Codex 内置浏览器可视窗口证据。当前会话无法保持内置浏览器交互，既有 Chrome CDP/headless 结果仍按无头测试边界记录；逐页面编辑、批量写入、加载失败、详情返回和发布环境窗口矩阵，以及 OIDC、公钥硬件 Passkey、CSRF/Cookie、多节点恢复和生产代理链仍未完成。

第十二批闭环证据：Phoenix `81586f6` 将字典类型写入后的刷新改为服务端分页读取，类型新增、编辑和删除不会把字典条目恢复成全量内存列表；读取失败保留旧页并显示稳定业务错误。admin-web `2179f8d` 将运行监控的强制下线失败统一显示业务错误码、业务含义和请求标识，成功后刷新监控快照。

本批次验证：Phoenix 集成测试 `445 passed`，admin-web `26 files / 147 tests passed`，类型检查和生产构建通过；三端错误码目录和接口路由集合检查通过。该批次仍不替代真实可视浏览器窗口验收，剩余页面矩阵、发布环境窗口、OIDC、公钥硬件 Passkey、CSRF/Cookie、多节点恢复和生产代理链继续保持未完成状态。

第十三批闭环证据：admin-web `d210b11` 将组织保存/删除、用户导入/批量删除和菜单角色目录/绑定读取失败统一接入 `ActionError`，错误面板保留业务码、业务含义和 `requestId`。Phoenix `c00101c` 将字典类型筛选改为服务端条目分页，筛选失败保留旧页和总数。

本批次验证：Phoenix 集成测试 `446 passed`；admin-web `26 files / 151 tests passed`，类型检查和生产构建通过；三端错误码目录、接口路由集合和源码行数检查通过。该批次仍未完成真实可视浏览器窗口、发布环境和安全边界证据。

第十四批闭环证据：admin-web `b548361` 将任务、个人资料、登录日志和操作审计的旧数据刷新失败改为安全业务文案，保留错误码、业务含义和请求标识，并补充旧数据保留测试。

本批次验证：admin-web `26 files / 155 tests passed`，类型检查和生产构建通过。该结果仍不替代真实可视浏览器窗口和发布环境验收。

Native `5b75636` 基线复核通过 `./gradlew test quarkusBuild`。测试日志中的限流事件和删除任务与调度触发交错产生的 `job not found` 仅作为非失败日志记录，暂列后续调度日志优化，不改变接口验收结论。

Native `bb832b1` 已修复该调度竞态日志。已删除任务被调度器再次触发时只记录跳过信息，不再输出错误堆栈；定向测试、全量测试和 Quarkus 构建均通过。

### 2026-11-17 继续验收记录

- Native `7d6d692`、Phoenix `cb07dbe` 和 admin-web 当前实现的字典条目关键词筛选已对齐，查询匹配值和显示名称，分页总数按筛选结果返回。
- Native `f388199`、admin-web `720aa70` 完成角色权限动态目录和逐项选择。权限目录读取支持 API Key 签发、权限目录读取或角色管理任一权限；权限写入保持 MFA step-up。
- Phoenix `62abb75` 和 admin-web `e4fc38d` 删除“管理工作台”顶部标题。两端保留相同的 `Keystone /` 上下文。
- admin-web `21b994d` 和 Phoenix `723b67f` 修复登录页短屏布局。Chrome CDP 真实窗口验证 320×568、360×667、390×844、480×736、768×844、1024×768 均无水平或垂直滚动，登录按钮和表单字段均可见。

本轮验证：Phoenix `447 passed`；admin-web `27 files / 158 tests passed`、类型检查和构建通过；Native 全量测试和 `quarkusBuild` 通过。当前 admin-web 使用 74 条 API 调用，Native/Phoenix 各提供 108 条 `/api/v1` 路由。Codex 内置浏览器在当前会话没有可保持交互的 `iab`，因此页面视觉证据使用 Chrome 回退窗口，不将其描述为内置浏览器证据。

补充验收：Phoenix `7af6e6d` 的权限目录接口已支持 `api-key:create`、`permission:read` 或 `role:manage` 任一权限，和 Native `f388199` 保持相同授权边界。Phoenix `4f205a9` 的角色权限表单与 admin-web `720aa70` 均从动态目录读取当前可授予项，支持搜索、分组、逐项选择和编辑预选。Phoenix 全量集成回归为 `449 passed`，角色权限定向回归为 `14 passed`。

### 2026-11-17 角色成员读取和登录界面增量

本轮已完成以下 Phoenix 提交：

- `edfc549` 按 `sys_user_role` 关联读取已分配和可分配成员，覆盖非首选角色；缺失角色返回 `404 resource_not_found`，空 `userIds` 分配和移除返回成功结果。
- `7825d23` 在角色列表行显示“成员”入口，LiveView 可以打开对应的成员管理面板。
- `a886aa7` 将用户表单的角色字段改为当前启用角色目录的多选框，编辑时保留已选角色，未选择角色时清空角色。
- `1e135dd` 将窄屏侧栏抽屉断点调整为 `850px`，点击“接口文档”打开 `/api/swagger` 前关闭抽屉。
- `2b9dca8` 将登录默认值设为 `operator`/`keystone`，并将 MFA 字段文案统一为“一次性验证码”。

该时点未完成项包括：Codex 内置浏览器无法保持交互；Phoenix 与 admin-web 仍有部分细节差异；通知页面 loading 状态未闭环；其余页面的逐页写操作、加载失败、错误反馈和完整错误矩阵、分页、编辑、批量操作结果及正式发布证据仍需继续补齐。成员详情 DTO 不是后端替换的阻塞项。

### 2026-11-17 通知和响应式布局补充

- Phoenix `4314f75` 增加站内通知异步 loading 状态，铃铛只处理通知列表和详情，不跳转公告管理；失败可重试，关闭时取消过期读取结果。
- admin-web `308269a` 将实际生效的响应式抽屉断点统一为 `850px`，清理旧 `68.75rem` 规则，避免中等窄屏布局错位。
- Phoenix `988ec65` 更新动态角色多选表单的组件验收，移除对旧角色文本输入的断言。

本轮验证：Phoenix 全量集成测试 `474 passed`；admin-web `27 files / 162 tests passed`、类型检查和生产构建通过；接口路由集合和业务错误码目录检查通过。Codex 内置浏览器当前仍无法保持交互窗口，因此没有新增内置浏览器可视证据；正式发布前仍需完成真实窗口、逐页面操作矩阵和安全/生产链路验收。

### 2026-11-17 导航图标补充

Phoenix `3d9776c` 将 LiveView 侧栏的 Unicode 图标替换为 SVG 图标组件，并同步 admin-web 的图标容器、颜色和交互样式。导航事件、权限可见性和响应式抽屉行为未改变。

本轮追加验证：Phoenix 全量集成测试 `474 passed`，导航定向测试 `3 passed`，严格编译、源码行数和差异检查通过；该提交不新增真实浏览器窗口证据。

### 2026-11-17 页面图标细节补充

Phoenix `c8e771d` 将用户、监控、组织、角色和菜单页面中的旧 Unicode 标记替换为与 admin-web 语义一致的 SVG 图标组件，保留权限、事件、状态颜色和响应式布局。

本轮页面组件和集成回归通过；Phoenix 全量集成测试仍为 `474 passed`。真实浏览器窗口证据仍未新增。

### 2026-11-17 admin-web CI 补充

admin-web `eba91c7` 新增固定 Action SHA 的 CI 工作流，执行锁文件安装、前端测试、类型检查和生产构建。该 CI 只证明代码级检查可自动运行，不替代真实浏览器窗口和 Native/Phoenix 后端切换验收。

本地验证：`pnpm test:run` 为 `27 files / 162 tests passed`，`pnpm typecheck` 和 `pnpm build` 通过，工作流静态检查通过。

### 2026-11-17 角色成员详情关闭闭环

Phoenix `467f486` 增加角色成员详情的“关闭”入口和 `close-role-users` 事件，清理选中角色、成员列表、反馈及分页状态；行为与 admin-web 的 `closeMembers()` 对齐。

本轮验证：角色页面定向测试 `19 passed`，Phoenix 全量集成测试 `474 passed`，严格编译、源码行数和差异检查通过。

### 2026-11-17 首屏监控读取失败反馈

Phoenix `31771cb` 在登录后读取默认运行监控。首次读取失败显示警示和“重试”按钮；已有快照刷新失败时保留旧数据并显示刷新反馈。监控读取职责拆分到 `MonitorSupport`，`AdminSupport` 保持兼容入口。非管理员账号收到 `permission_denied` 时转为可恢复的监控不可用状态，LiveView 不再崩溃。

本轮验证：监控组件和页面定向测试 `13 passed`；Phoenix 全量集成测试 `476 passed`；`mix compile --warnings-as-errors`、`mix check.source_lines`、格式检查和 `git diff --check` 通过。

监控读取目前仍在事件处理中同步执行。组件已提供 loading 状态，但需要异步读取后才能在等待期间展示。其他页面的首次读取错误、真实浏览器窗口、Native/Phoenix 后端切换窗口验收，以及 OIDC、公钥硬件 Passkey、浏览器 CSRF/Cookie、多节点恢复、生产代理链和正式发布证据仍未完成。

### 2026-11-17 路由检查和页面图标补充

Phoenix `df43ebb` 修复路由检查脚本遗漏三元表达式路径的问题，并覆盖模板路径参数、重复项和请求体中的非路由字符串。检查结果更新为 admin-web 使用 79 条 API 路由；Native 和 Phoenix 的 108 条 `/api/v1` 路由仍一致。

Phoenix `6129e6a` 将任务、岗位和公告表格及空状态中的旧字符标记改为 SVG 图标，并对齐图标尺寸。组件定向测试 `13 passed`；严格编译、源码行数、格式和差异检查通过。本轮没有新增真实浏览器窗口证据。
