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
| MFA 登录和 step-up | 401 二次认证请求结构、AAL2 短时令牌、策略要求或 `enforce=true` 时拒绝 AAL1 | Phoenix `a5d5320` 已按 `mfa_required` 对齐普通敏感写，并对用户导入和 Passkey 注册使用 `enforce=true`；真实 MFA 仪式仍需补充 |
| 列表查询 | 字段名称、分页 `items/page/size/total`、筛选参数、空结果 | Native/Phoenix 控制器契约测试；需用同一 admin-web 页面双后端核验 |
| 写操作 | 请求字段、201/200/204、`deleted`/`triggered` 结果、验证错误 | Native/Phoenix HTTP 回归；需覆盖发布版本构建 |
| 错误处理 | `success/data/message/error`、401/403/404/422/503 分类 | admin-web 仅对网络错误允许开发 Mock 回退；HTTP 错误必须显示 |
| 路由集合 | 业务方法与路径集合相同，无重复和过时入口 | 109 条业务路由集合核对已通过 |

## 页面验收条件

对每个后端重复以下流程。页面、操作顺序和筛选条件保持一致，结果分别记录：

- 登录、刷新页面、注销和会话失效返回登录页。
- 监控页读取真实状态，显示后端来源和未提供指标；空在线会话显示明确空态。
- 用户页使用用户名和展示名筛选，打开新增/编辑，验证 enabled、角色、数据范围错误反馈。
- 角色、部门、岗位、菜单页验证筛选、层级、状态、删除确认和错误反馈。
- API Key 页验证元数据列表、签发一次性密钥、轮换、撤销和 AAL2 step-up。
- 审计页验证用户、动作、资源筛选、分页和导出；页面保持只读交互。
- 任务页验证筛选、编辑、启停、执行、日志和批量删除。
- 配置、字典、公告页验证筛选、CRUD、启用状态、公告发布/取消发布和空态。
- 个人资料页验证资料保存、密码更新的 AAL2 step-up 和会话失效提示。

个人资料密码更新的请求体统一为 `{"password": "..."}`。Native 和 Phoenix 都在 AAL2 step-up 通过后更新密码并撤销当前会话，LiveView 表单与 admin-web 均只要求填写新密码。

Phoenix MFA parity 提交为 `a5d5320`：普通敏感写操作按账号的 `mfa_required` 策略检查 step-up，用户导入和 Passkey 注册使用 `enforce=true`，始终要求 AAL2 step-up。

Phoenix LiveView 管理页面同时以 admin-web 的颜色、布局、筛选栏、表格、卡片、徽标、空态、错误反馈、分页和模态框为视觉基准。Phoenix 静态资源后置加载 admin-web 基准样式，并通过兼容样式保留 LiveView 事件和认证状态。LiveView 重实现不改变 `/api/v1` 接口约定。

2026-11-15 的验收使用同一份 admin-web 构建并设置 `VITE_ENABLE_MOCK=false`。Phoenix 和 Native
均已完成真实浏览器登录、侧栏导航、通知入口、用户图形个人资料入口和页面读取。Native 监控接口返回
`PARTIAL`，Phoenix 监控页返回 BEAM/OTP 运行时数据；两端都显示后端来源和缺失指标状态。Native
和 Phoenix 均在 280、320、390、768 和 1280 视口完成宽度检查，未发现横向溢出。Native
admin-web 已完成用户新增和删除真实窗口流程：创建唯一测试用户时先显示密码策略错误，再使用合规密码成功创建；
列表刷新后选择该用户、确认删除并完成测试数据清理。Phoenix API 通过同一 admin-web 在端口 5176、使用
`admin/123456` 登录后完成对应的用户新增、列表刷新、选择、删除确认和清理。除用户新增和删除流程外，
两端仍未完成逐页写操作、筛选、导出、批量操作、错误反馈和模态框结果的完整真实窗口矩阵。

Phoenix 补充窗口记录使用 `VITE_API_PROXY_TARGET=http://127.0.0.1:4000` 和前端端口 `5176`。
同一份 admin-web 使用 `ag1/123456` 登录成功，13 个可见菜单页面、通知入口、顶栏用户图形入口、
监控帮助展开和关闭均通过验收，并在 280、320、390、768 和 1280 视口完成宽度矩阵检查。

Native 和 Phoenix 的同一份 admin-web 还完成了角色、组织、岗位、菜单、API Key、操作审计、登录日志、
系统配置和字典页面的无结果筛选与重置；用户、角色、组织、岗位、菜单、系统配置、字典、通知和定时任务的
新增弹窗均能打开并取消关闭。两端的空态、查询和模态框关闭结果一致。

用户、角色、岗位、操作审计和登录日志页面的“导出 Excel”在 Native 和 Phoenix 均通过真实窗口检查。
Phoenix 角色导出的 `406` 已在 `220fdde` 修复，API 管道现在接受 XLSX MIME。

Phoenix LiveView 已完成共享壳、登录、账号、组织、系统和任务页面的主要视觉重实现。侧栏、顶栏、
颜色令牌、卡片、筛选区、按钮、表格、徽标、状态 footer、用户图形个人资料入口和侧栏菜单结构已经按 admin-web
对齐。页面使用同一份 admin-web 样式基准，兼容样式只处理 LiveView 的导航和认证差异。窄屏布局使用流式宽度，
没有设置固定页面最小宽度；内置浏览器在 280、320、390、768 和 1280 视口验证了 Native admin-web 和 Phoenix 页面没有横向溢出。
Phoenix 和 admin-web 可见菜单均为 13 项，已移除“工作台”、个人资料菜单和“系统”分组标题；`/dashboard` 仍保留为兼容深链接。发布前仍需逐页补全导出、批量操作、加载状态、错误反馈、分页、编辑和写操作结果。

监控帮助按钮已在两个前端实现展开和关闭，显示系统 API、缺失指标和 `PARTIAL` 状态的阅读说明。侧栏仅保留“运维审计”分组标题；系统配置、字典管理和通知公告直接列在其后，两个前端的菜单结构一致。

监控页的状态栏、资源卡片、在线会话、节点详情、80% 关注阈值、系统 API 来源和无采样空态已按 admin-web 组件层级重实现。Phoenix 缺失资源字段统一显示 `—`，不会把缺失值误读为 `0%`。Phoenix 监控页、任务页、组织页和系统页分别在提交 `f4c4e7b`、`65d0cd2` 和 `9431783` 中完成页面模板重实现；admin-web 响应式修复已在 `661fb2a` 推送，工作台入口移除在 `0d34206` 推送，通知发布错误反馈在 `193ec91` 推送，监控帮助和侧栏分组对齐分别在 `379d7f8` 和 `80031cc` 推送，Phoenix 监控帮助状态修复在 `c4f39bd` 推送，Phoenix MFA parity 在 `a5d5320` 推送，两个前端删除“系统”分组标题分别在 `13bcfeb` 和 `65ac3cf` 推送。

2026-11-15 登录页视觉复核使用同一内置浏览器视口分别打开 `http://127.0.0.1:5173/login` 和
`http://127.0.0.1:4000/`。两端的登录布局、logo、标题、登录卡片、输入框图标、按钮和脚注关键元素位置与尺寸一致；两端 `document.documentElement.scrollHeight` 均等于 `clientHeight`，登录页没有页面滚动条。Phoenix 对应提交为 `b975a6c`、`bc9ae1d`，admin-web 对应提交为 `904ffe1`、`f91b4fb`。

Phoenix 审计页已按 admin-web 的只读约定移除删除按钮和操作列，保留后端事件兼容已有调用；对应提交为 `ace60dd`。Phoenix 个人资料页已按 admin-web 改为只填写新密码，密码更新接口统一使用单个 `password` 字段，并在 AAL2 通过后撤销当前会话；对应提交为 `b4c92cb`。重启当前 Phoenix 服务后，内置浏览器确认个人资料页只渲染 `input[name="password"]`，不再渲染 `oldPassword` 或 `newPassword`。

Phoenix 任务页已补齐与 admin-web 一致的当前页勾选、全选、批量删除确认、删除反馈和筛选后选择状态清理；对应提交为 `4ac1dc7`。原有单项编辑、启停、执行、取消和权限检查保持不变。

## 发布前证据

每个正式版本必须保留以下证据：

1. Native 和 Phoenix 各自的完整测试、严格编译和源码行数结果。
2. 同一 admin-web commit 的 `pnpm test:run`、`pnpm typecheck` 和 `pnpm build`。
3. `VITE_ENABLE_MOCK=false` 下分别连接 Native、Phoenix 的真实窗口截图或操作记录。
4. 两个后端的路由集合差异、旧接口搜索和数据库迁移状态。
5. 未完成的 OIDC、公钥硬件 Passkey、CSRF/Cookie、多节点和生产代理检查必须单独标记为证据缺口，不能写成页面通过。

当前状态：后端业务路由集合、DTO 适配和 Native/Phoenix HTTP 接口对齐已完成；旧接口和重复接口已从正式业务路由集合删除；同一份 admin-web 已在 `VITE_ENABLE_MOCK=false` 下分别连接 Native 和 Phoenix，两个后端均完成真实浏览器登录、导航、个人资料入口和 280、320、390、768、1280 宽度检查。Native 和 Phoenix 的用户新增、列表刷新、选择、删除确认和测试数据清理已完成真实窗口验收；两端还完成了 9 个列表页的无结果筛选与重置、9 类新增弹窗的打开和取消关闭，以及用户、角色、岗位、操作审计和登录日志的 Excel 导出。用户可见后端来源和错误文案已泛化为系统 API。Phoenix LiveView 已增加 admin-web 对齐的深链接、页面模板和响应式壳；批量操作、加载状态、错误反馈、分页、编辑和逐页写操作矩阵、真实 MFA 仪式以及 OIDC、硬件 Passkey、CSRF/Cookie、多节点和生产代理链仍是发布证据缺口。
