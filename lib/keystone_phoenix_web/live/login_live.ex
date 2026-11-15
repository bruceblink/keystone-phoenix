defmodule KeystonePhoenixWeb.LoginLive do
  use Phoenix.LiveView

  import Phoenix.Component
  import KeystonePhoenixWeb.Live.AdminPages.Accounts
  import KeystonePhoenixWeb.Live.AdminPages.ApiKeys
  import KeystonePhoenixWeb.Live.AdminPages.Operations
  import KeystonePhoenixWeb.Live.AdminPages.Organization
  import KeystonePhoenixWeb.Live.AdminPages.System

  alias KeystonePhoenix.Auth
  alias KeystonePhoenix.Auth.Captcha
  alias KeystonePhoenix.Auth.LoginLimiter
  alias KeystonePhoenix.Log
  alias KeystonePhoenixWeb.Live.AdminSupport
  alias KeystonePhoenixWeb.Live.AdminPages.Navigation
  alias KeystonePhoenixWeb.Live.Authentication
  alias KeystonePhoenixWeb.Live.LoginState
  alias KeystonePhoenixWeb.Live.AdminEvents.Accounts, as: AccountsEvents
  alias KeystonePhoenixWeb.Live.AdminEvents.Config, as: ConfigEvents
  alias KeystonePhoenixWeb.Live.AdminEvents.Operations, as: OperationsEvents
  alias KeystonePhoenixWeb.Live.AdminEvents.Organization, as: OrganizationEvents
  alias KeystonePhoenixWeb.Live.AdminEvents.System, as: SystemEvents
  alias KeystonePhoenixWeb.Live.AdminEvents.Audit, as: AuditEvents
  alias KeystonePhoenixWeb.Live.AdminEvents.Security, as: SecurityEvents
  alias KeystonePhoenixWeb.Live.LoginEvents

  @impl true
  def mount(_params, _session, socket) do
    remote_ip = connect_remote_ip(socket)

    socket =
      allow_upload(socket, :avatar,
        accept: ~w(.bmp .gif .jpg .jpeg .png .webp),
        max_entries: 1,
        max_file_size: 50 * 1024 * 1024
      )

    socket =
      allow_upload(socket, :user_import,
        accept: ~w(.xlsx),
        max_entries: 1,
        max_file_size: 50 * 1024 * 1024
      )

    {:ok,
     socket
     |> LoginState.reset()
     |> assign(remote_ip: remote_ip)
     |> Authentication.refresh_captcha()
     |> attach_hook(:authenticate_event, :handle_event, &Authentication.guard_event/3)
     |> attach_hook(:authenticate_info, :handle_info, &Authentication.guard_info/2)}
  end

  @impl true
  def handle_params(_params, uri, socket) do
    requested_panel = Navigation.panel_for_path(uri)

    if AdminSupport.authenticated_socket?(socket) do
      {:noreply, assign(socket, active_panel: requested_panel)}
    else
      {:noreply, assign(socket, requested_panel: requested_panel)}
    end
  end

  @impl true
  def handle_event("login", %{"username" => username, "password" => password} = params, socket) do
    username = String.trim(username)

    result =
      case LoginLimiter.check_liveview(username, liveview_ip(socket)) do
        :allow ->
          case Captcha.validate(params["captchaCode"], socket.assigns.captcha_key) do
            :ok -> Auth.login_plaintext(username, password)
            error -> error
          end

        {:deny, retry_after} ->
          {:error, {:rate_limited, retry_after}}

        {:error, reason} when reason in [:capacity, :unavailable] ->
          {:error, :login_limiter_unavailable}
      end

    case result do
      {:ok, tokens} ->
        {:noreply, LoginEvents.authenticated_socket(socket, username, tokens)}

      {:mfa_required, %{challenge: challenge, username: challenge_username}} ->
        {:noreply,
         assign(socket,
           username: challenge_username,
           password: "",
           login_error: nil,
           mfa_challenge: challenge,
           mfa_username: challenge_username,
           mfa_code: "",
           mfa_error: nil
         )}

      {:error, :already_logged_in} ->
        Log.record_login_event(username, 0, "该账号已经登录")
        login_error(socket, username, "该账号已经登录，请先退出或使用 API 的 forceLogin 接管")

      {:error, {:rate_limited, retry_after}} ->
        Log.record_login_event(username, 0, "登录尝试过于频繁")
        login_error(socket, username, "登录尝试过于频繁，请在 #{retry_after} 秒后重试")

      {:error, :login_limiter_unavailable} ->
        Log.record_login_event(username, 0, "限流服务暂不可用")
        login_error(socket, username, "登录服务暂不可用，请稍后重试")

      {:error, reason} when reason in [:capacity, :unavailable] ->
        Log.record_login_event(username, 0, "认证会话暂不可用")
        login_error(socket, username, "认证会话暂不可用，请稍后重试")

      {:error, :mfa_enrollment_required} ->
        Log.record_login_event(username, 0, "账号尚未完成 MFA 注册")
        login_error(socket, username, "账号需要先完成 MFA 注册")

      {:error, reason} when reason in [:captcha_required, :captcha_invalid, :captcha_expired] ->
        message = captcha_error(reason)
        Log.record_login_event(username, 0, message)
        login_error(socket, username, message)

      _ ->
        Log.record_login_event(username, 0, "用户名或密码错误")
        login_error(socket, username, "用户名或密码错误")
    end
  end

  def handle_event("login", _params, socket) do
    {:noreply, assign(socket, login_error: "请输入用户名和密码")}
  end

  def handle_event("verify-login-mfa", params, socket),
    do: LoginEvents.handle_event("verify-login-mfa", params, socket)

  def handle_event("cancel-login-mfa", params, socket),
    do: LoginEvents.handle_event("cancel-login-mfa", params, socket)

  def handle_event("begin-liveview-step-up", params, socket),
    do: LoginEvents.handle_event("begin-liveview-step-up", params, socket)

  def handle_event("verify-liveview-step-up", params, socket),
    do: LoginEvents.handle_event("verify-liveview-step-up", params, socket)

  def handle_event("cancel-liveview-step-up", params, socket),
    do: LoginEvents.handle_event("cancel-liveview-step-up", params, socket)

  def handle_event("refresh-captcha", _params, socket) do
    case LoginLimiter.check_captcha(liveview_ip(socket)) do
      :allow ->
        {:noreply, Authentication.refresh_captcha(socket)}

      {:deny, retry_after} ->
        {:noreply, assign(socket, login_error: "验证码刷新过于频繁，请在 #{retry_after} 秒后重试")}

      {:error, reason} when reason in [:capacity, :unavailable] ->
        {:noreply, assign(socket, login_error: "验证码服务暂不可用，请稍后重试")}
    end
  end

  def handle_event("close-modal", _params, socket) do
    {:noreply, assign(socket, active_modal: nil)}
  end

  @impl true
  def handle_event("toggle-sidebar", _params, socket),
    do: {:noreply, update(socket, :sidebar_open, &(!&1))}

  @impl true
  def handle_event("close-sidebar", _params, socket),
    do: {:noreply, assign(socket, sidebar_open: false)}

  @impl true
  def handle_event("show-panel", %{"panel" => panel}, socket)
      when panel in [
             "overview",
             "dashboard",
             "depts",
             "posts",
             "roles",
             "menus",
             "api-keys",
             "notices",
             "logs",
             "login-logs",
             "operation-logs",
             "users",
             "configs",
             "dicts",
             "jobs",
             "job-logs",
             "profile",
             "monitor"
           ] do
    panel = Navigation.normalize_panel(panel)

    if AdminSupport.panel_allowed?(socket, panel) do
      socket = assign(socket, sidebar_open: false)

      cond do
        panel == "profile" ->
          {:noreply, AdminSupport.assign_profile(socket)}

        panel == "monitor" ->
          socket = assign(socket, page_nums: Map.put(socket.assigns.page_nums, "online-users", 1))
          {:noreply, AdminSupport.assign_monitor(socket)}

        panel in ["login-logs", "operation-logs"] ->
          {:noreply,
           assign(socket,
             active_panel: panel,
             log_feedback: nil
           )}

        panel == "api-keys" ->
          {:noreply,
           assign(socket,
             active_panel: panel,
             api_key_rows: AdminSupport.load_api_keys_for_socket(socket),
             api_key_feedback: nil,
             issued_api_key: nil
           )}

        panel == "users" and not AdminSupport.admin_socket?(socket) ->
          {:noreply,
           assign(socket,
             active_panel: panel,
             user_rows: AdminSupport.load_users_for_socket(socket)
           )}

        true ->
          {:noreply, assign(socket, active_panel: panel)}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("show-panel", _params, socket), do: {:noreply, socket}

  def handle_event("paginate", %{"panel" => panel, "page" => page}, socket)
      when panel in [
             "users",
             "posts",
             "jobs",
             "job-logs",
             "dict-data",
             "login-logs",
             "operation-logs",
             "online-users",
             "role-users-allocated",
             "role-users-unallocated"
           ] do
    case Integer.parse(to_string(page)) do
      {page, ""} when page > 0 ->
        socket = assign(socket, page_nums: Map.put(socket.assigns.page_nums, panel, page))

        if panel == "online-users" and AdminSupport.panel_allowed?(socket, "monitor") do
          {:noreply, AdminSupport.assign_monitor(socket)}
        else
          {:noreply, socket}
        end

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("paginate", _params, socket), do: {:noreply, socket}

  @organization_events ~w(refresh-depts new-dept edit-dept save-dept toggle-dept-status delete-dept refresh-posts export-posts new-post edit-post save-post toggle-post-status delete-post refresh-roles export-roles new-role edit-role save-role toggle-role-selection toggle-all-role-selection toggle-role-status delete-role select-role assign-role-user unassign-role-user refresh-menus new-menu edit-menu save-menu toggle-menu-status delete-menu)
  @accounts_events ~w(filter-users reset-user-filter refresh-users export-users new-user-import toggle-user-selection toggle-all-user-selection delete-users import-users new-user edit-user save-user toggle-user-status delete-user reset-user-password save-profile change-profile-password update-profile-avatar save-profile-avatar-upload)
  @config_events ~w(refresh-config delete-config filter-configs reset-config-filter new-config edit-config save-config)
  @system_events ~w(refresh-dicts select-dict-type new-dict-type edit-dict-type save-dict-type delete-dict-type new-dict-data edit-dict-data save-dict-data delete-dict-data refresh-logs refresh-login-logs refresh-operation-logs new-notice edit-notice cancel-notice save-notice toggle-notice-status publish-notice toggle-notice-selection toggle-all-notice-selection delete-notice delete-notices refresh-notices filter-notices reset-notice-filter delete-login-log delete-operation-log)
  @audit_events ~w(filter-login-logs reset-login-log-filter filter-operation-logs reset-operation-log-filter filter-dict-types reset-dict-type-filter export-login-logs export-operation-logs)
  @operations_events ~w(refresh-jobs filter-jobs reset-job-filter toggle-job-selection toggle-all-job-selection select-job new-job edit-job save-job delete-job delete-jobs run-job cancel-job toggle-job-status refresh-job-logs refresh-monitor toggle-monitor-help logout-online-user)
  @security_events ~w(refresh-api-keys new-api-key save-api-key rotate-api-key revoke-api-key filter-api-keys dismiss-api-key-secret)

  @impl true
  def handle_event(event, params, socket) when event in @organization_events,
    do: OrganizationEvents.handle_event(event, params, socket)

  def handle_event(event, params, socket) when event in @accounts_events,
    do: AccountsEvents.handle_event(event, params, socket)

  def handle_event(event, params, socket) when event in @config_events,
    do: ConfigEvents.handle_event(event, params, socket)

  def handle_event(event, params, socket) when event in @system_events,
    do: SystemEvents.handle_event(event, params, socket)

  def handle_event(event, params, socket) when event in @audit_events,
    do: AuditEvents.handle_event(event, params, socket)

  def handle_event(event, params, socket) when event in @operations_events,
    do: OperationsEvents.handle_event(event, params, socket)

  def handle_event(event, params, socket) when event in @security_events,
    do: SecurityEvents.handle_event(event, params, socket)

  @impl true
  def handle_event("logout", _params, socket) do
    Auth.logout(socket.assigns.refresh_token)
    {:noreply, socket |> LoginState.reset() |> Authentication.refresh_captcha()}
  end

  @impl true
  def handle_event(_event, _params, socket), do: {:noreply, socket}

  @impl true
  def handle_info({:admin_job_finished, _job_id, result}, socket) do
    feedback =
      case result do
        :ok -> "任务已执行并写入运行日志"
        {:skipped, :already_running} -> "任务正在执行，本次触发已跳过"
        {:error, :not_found} -> "找不到指定任务"
        {:error, reason} -> "任务执行失败：#{inspect(reason)}"
        _ -> "任务状态未知，请检查运行日志"
      end

    reload =
      if AdminSupport.admin_socket?(socket) do
        [
          job_rows: AdminSupport.load_jobs(),
          job_log_rows: AdminSupport.load_job_logs()
        ]
      else
        [
          job_rows: AdminSupport.load_jobs_for_socket(socket),
          job_log_rows: AdminSupport.load_job_logs_for_socket(socket)
        ]
      end

    {:noreply, assign(socket, Keyword.put(reload, :job_feedback, feedback))}
  end

  defp login_error(socket, username, message) do
    {:noreply,
     socket
     |> Authentication.refresh_captcha()
     |> assign(username: username, password: "", login_error: message)}
  end

  defp captcha_error(:captcha_required), do: "请输入验证码"
  defp captcha_error(:captcha_invalid), do: "验证码错误，请重试"
  defp captcha_error(:captcha_expired), do: "验证码已过期，请重试"

  defp liveview_ip(socket) do
    Map.get(socket.assigns, :remote_ip)
  end

  defp connect_remote_ip(socket) do
    case Phoenix.LiveView.get_connect_info(socket, :peer_data) do
      %{address: address} -> address
      _ -> nil
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <!doctype html>
    <html lang="zh-CN">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <meta name="csrf-token" content={Plug.CSRFProtection.get_csrf_token()} />
        <title>Keystone Admin</title>
        <link rel="stylesheet" href="/css/keystone.css" />
        <link rel="stylesheet" href="/css/keystone-responsive.css" />
        <link rel="stylesheet" href="/css/admin-web.css" />
        <link rel="stylesheet" href="/css/admin-web-compat.css" />
      </head>
      <body>
        <main class={if @current_user, do: "app-main dashboard-main", else: "app-main login-main"}>
          <section class={if @current_user, do: "shell app-shell dashboard-shell", else: "login-page"}>
            <%= if @current_user do %>
              <div class="dashboard">
                  <div class={"sidebar-brand sidebar-head#{if @sidebar_open, do: " sidebar-open", else: ""}"}>
                  <div class="brand-mark" aria-hidden="true"><svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="M22 12h-4l-3 9L9 3l-3 9H2" /></svg></div>
                  <div>
                    <strong>KEYSTONE</strong>
                    <span>Admin Console</span>
                  </div>
                </div>
                <div class="topbar dashboard-topbar">
                  <button type="button" class="mobile-menu" phx-click="toggle-sidebar" aria-label={if @sidebar_open, do: "关闭导航", else: "打开导航"} aria-expanded={@sidebar_open}><svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M4 6h16M4 12h16M4 18h16" /></svg></button>
                  <div class="topbar-context">
                    <span class="context-kicker">Keystone</span><span class="context-separator">/</span><span>管理工作台</span>
                  </div>
                  <div class="user topbar-actions user-menu">
                    <button type="button" class="icon-button" phx-click="show-panel" phx-value-panel="notices" aria-label="通知">
                      <svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M18 8a6 6 0 0 0-12 0c0 7-3 7-3 9h18c0-2-3-2-3-9" /><path d="M13.73 21a2 2 0 0 1-3.46 0" /></svg><span class="notification-dot" aria-hidden="true"></span>
                    </button>
                    <button type="button" class="user-profile-button" phx-click="show-panel" phx-value-panel="profile" aria-label="打开个人资料">
                      <span class="user-avatar" aria-hidden="true"><%= String.first(to_string(@current_user["nickname"] || @current_user["username"])) %></span>
                      <span>
                        <strong><%= @current_user["nickname"] || @current_user["username"] %></strong>
                        <span><%= @current_user["role"] || @current_user["roleName"] || "管理员" %></span>
                      </span>
                      <svg class="profile-chevron" xmlns="http://www.w3.org/2000/svg" width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="m6 9 6 6 6-6" /></svg>
                    </button>
                    <button type="button" class="button button-ghost logout-button secondary" phx-click="logout" phx-disable-with="退出中…"><svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4" /><path d="m16 17 5-5-5-5" /><path d="M21 12H9" /></svg><span>退出</span></button>
                  </div>
                </div>
                <button :if={@sidebar_open} type="button" class="sidebar-scrim" phx-click="toggle-sidebar" aria-label="关闭导航"></button>
                <p :if={@mfa_step_up_notice} id="mfa-step-up-notice" class="notice" role="status"><%= @mfa_step_up_notice %></p>
                <div :if={@mfa_step_up_required} id="mfa-step-up-panel" class="card" role="alert">
                  <h3>需要二次认证</h3>
                  <p :if={@mfa_step_up_error} class="error"><%= @mfa_step_up_error %></p>
                  <%= if @mfa_step_up_challenge do %>
                    <form id="mfa-step-up-form" phx-submit="verify-liveview-step-up">
                      <label for="mfa-step-up-code">MFA 验证码</label>
                      <input id="mfa-step-up-code" name="code" inputmode="numeric" autocomplete="one-time-code" required />
                      <button type="submit" phx-disable-with="验证中…">验证并继续</button>
                      <button type="button" class="secondary" phx-click="cancel-liveview-step-up">取消</button>
                    </form>
                  <% else %>
                    <button type="button" phx-click="begin-liveview-step-up">开始二次认证</button>
                    <button type="button" class="secondary" phx-click="cancel-liveview-step-up">取消</button>
                  <% end %>
                </div>
                <%= if Enum.any?(Map.values(@panel_access)) do %>
                  <nav class={"module-nav primary-nav#{if @sidebar_open, do: " sidebar-open", else: ""}"} aria-label="主导航">
                    <button :if={@panel_access["monitor"]} type="button" class={if @active_panel == "monitor", do: "nav-item active", else: "nav-item"} phx-click="show-panel" aria-current={if @active_panel == "monitor", do: "page"} phx-value-panel="monitor"><span class="nav-icon" aria-hidden="true">⌁</span><span>运行监控</span></button>
                    <button :if={@panel_access["users"]} type="button" class={if @active_panel == "users", do: "nav-item active", else: "nav-item"} phx-click="show-panel" aria-current={if @active_panel == "users", do: "page"} phx-value-panel="users"><span class="nav-icon" aria-hidden="true">◉</span><span>用户与权限</span></button>
                    <button :if={@panel_access["roles"]} type="button" class={if @active_panel == "roles", do: "nav-item active", else: "nav-item"} phx-click="show-panel" aria-current={if @active_panel == "roles", do: "page"} phx-value-panel="roles"><span class="nav-icon" aria-hidden="true">◌</span><span>角色管理</span></button>
                    <button :if={@panel_access["depts"]} type="button" class={if @active_panel == "depts", do: "nav-item active", else: "nav-item"} phx-click="show-panel" aria-current={if @active_panel == "depts", do: "page"} phx-value-panel="depts"><span class="nav-icon" aria-hidden="true">▥</span><span>组织结构</span></button>
                    <button :if={@panel_access["posts"]} type="button" class={if @active_panel == "posts", do: "nav-item active", else: "nav-item"} phx-click="show-panel" aria-current={if @active_panel == "posts", do: "page"} phx-value-panel="posts"><span class="nav-icon" aria-hidden="true">▤</span><span>岗位管理</span></button>
                    <button :if={@panel_access["menus"]} type="button" class={if @active_panel == "menus", do: "nav-item active", else: "nav-item"} phx-click="show-panel" aria-current={if @active_panel == "menus", do: "page"} phx-value-panel="menus"><span class="nav-icon" aria-hidden="true">≡</span><span>菜单与权限</span></button>
                    <button :if={@panel_access["api-keys"]} type="button" class={if @active_panel == "api-keys", do: "nav-item active", else: "nav-item"} phx-click="show-panel" aria-current={if @active_panel == "api-keys", do: "page"} phx-value-panel="api-keys"><span class="nav-icon" aria-hidden="true">⚿</span><span>API Key</span></button>
                    <span class="nav-section-title nav-label nav-label-spaced">运维审计</span>
                    <button :if={@panel_access["operation-logs"]} type="button" class={if @active_panel == "operation-logs", do: "nav-item active", else: "nav-item"} phx-click="show-panel" aria-current={if @active_panel == "operation-logs", do: "page"} phx-value-panel="operation-logs"><span class="nav-icon" aria-hidden="true">◫</span><span>操作审计</span></button>
                    <button :if={@panel_access["login-logs"]} type="button" class={if @active_panel == "login-logs", do: "nav-item active", else: "nav-item"} phx-click="show-panel" aria-current={if @active_panel == "login-logs", do: "page"} phx-value-panel="login-logs"><span class="nav-icon" aria-hidden="true">◴</span><span>登录日志</span></button>
                    <button :if={@panel_access["jobs"]} type="button" class={if @active_panel == "jobs", do: "nav-item active", else: "nav-item"} phx-click="show-panel" aria-current={if @active_panel == "jobs", do: "page"} phx-value-panel="jobs"><span class="nav-icon" aria-hidden="true">☷</span><span>定时任务</span></button>
                    <button :if={@panel_access["configs"]} type="button" class={if @active_panel == "configs", do: "nav-item active", else: "nav-item"} phx-click="show-panel" aria-current={if @active_panel == "configs", do: "page"} phx-value-panel="configs"><span class="nav-icon" aria-hidden="true">⚙</span><span>系统配置</span></button>
                    <button :if={@panel_access["dicts"]} type="button" class={if @active_panel == "dicts", do: "nav-item active", else: "nav-item"} phx-click="show-panel" aria-current={if @active_panel == "dicts", do: "page"} phx-value-panel="dicts"><span class="nav-icon" aria-hidden="true">▢</span><span>字典管理</span></button>
                    <button :if={@panel_access["notices"]} type="button" class={if @active_panel == "notices", do: "nav-item active", else: "nav-item"} phx-click="show-panel" aria-current={if @active_panel == "notices", do: "page"} phx-value-panel="notices"><span class="nav-icon" aria-hidden="true">⌁</span><span>通知公告</span></button>
                  </nav>
                  <div class={"sidebar-foot#{if @sidebar_open, do: " sidebar-open", else: ""}"}><div class="status-dot"><span></span> API 正常</div><span class="sidebar-version">v0.1.0 · dev</span></div>
                  <div class="page-content">
                  <%= case @active_panel do %>
                    <% "depts" -> %>
                      <.departments dept_rows={@dept_rows} dept_form={@dept_form} dept_feedback={@dept_feedback} active_modal={@active_modal} read_only={@read_only} permissions={@permissions} />
                    <% "posts" -> %>
                      <.posts post_rows={@post_rows} post_form={@post_form} post_feedback={@post_feedback} active_modal={@active_modal} page_num={@page_nums["posts"]} page_size={@page_sizes["posts"]} read_only={@read_only} permissions={@permissions} />
                    <% "roles" -> %>
                      <.roles role_rows={@role_rows} role_form={@role_form} role_feedback={@role_feedback} menu_rows={@menu_rows} active_modal={@active_modal} selected_role_id={@selected_role_id} selected_role_name={@selected_role_name} allocated_role_user_rows={@allocated_role_user_rows} unallocated_role_user_rows={@unallocated_role_user_rows} role_user_feedback={@role_user_feedback} allocated_page_num={@page_nums["role-users-allocated"]} unallocated_page_num={@page_nums["role-users-unallocated"]} role_user_page_size={@page_sizes["role-users-allocated"]} read_only={@read_only} permissions={@permissions} />
                    <% "menus" -> %>
                      <.menus menu_rows={@menu_rows} menu_form={@menu_form} menu_feedback={@menu_feedback} active_modal={@active_modal} read_only={@read_only} />
                    <% "users" -> %>
                      <.users user_rows={@user_rows} user_form={@user_form} user_feedback={@user_feedback} active_modal={@active_modal} dept_rows={@dept_rows} post_rows={@post_rows} role_rows={@role_rows} page_num={@page_nums["users"]} page_size={@page_sizes["users"]} read_only={@read_only} permissions={@permissions} user_import_upload={@uploads.user_import} />
                    <% "api-keys" -> %>
                      <.api_keys api_key_rows={@api_key_rows} api_key_feedback={@api_key_feedback} api_key_form={@api_key_form} api_key_query={@api_key_query} api_key_status={@api_key_status} issued_api_key={@issued_api_key} permissions={@permissions} active_modal={@active_modal} read_only={@read_only} />
                    <% "configs" -> %>
                      <.configs config_rows={@config_rows} config_form={@config_form} config_feedback={@config_feedback} active_modal={@active_modal} read_only={@read_only} />
                    <% "dicts" -> %>
                      <.dicts dict_type_rows={@dict_type_rows} dict_data_rows={@dict_data_rows} dict_type_form={@dict_type_form} dict_data_form={@dict_data_form} selected_dict_type={@selected_dict_type} dict_feedback={@dict_feedback} active_modal={@active_modal} dict_data_page_num={@page_nums["dict-data"]} dict_data_page_size={@page_sizes["dict-data"]} dict_type_filter={@dict_type_filter} read_only={@read_only} />
                    <% "notices" -> %>
                      <.notices notice_rows={@notice_rows} notice_form={@notice_form} notice_feedback={@notice_feedback} active_modal={@active_modal} read_only={@read_only} />
                    <% "login-logs" -> %>
                      <.logs kind="login" login_log_rows={@login_log_rows} operation_log_rows={@operation_log_rows} log_feedback={@log_feedback} login_log_filter={@login_log_filter} operation_log_filter={@operation_log_filter} login_page_num={@page_nums["login-logs"]} operation_page_num={@page_nums["operation-logs"]} page_size={@page_sizes["login-logs"]} read_only={@read_only} />
                    <% "operation-logs" -> %>
                      <.logs kind="operation" login_log_rows={@login_log_rows} operation_log_rows={@operation_log_rows} log_feedback={@log_feedback} login_log_filter={@login_log_filter} operation_log_filter={@operation_log_filter} login_page_num={@page_nums["login-logs"]} operation_page_num={@page_nums["operation-logs"]} page_size={@page_sizes["operation-logs"]} read_only={@read_only} />
                    <% "jobs" -> %>
                      <.jobs job_rows={@job_rows} job_form={@job_form} job_targets={@job_targets} job_feedback={@job_feedback} active_modal={@active_modal} page_num={@page_nums["jobs"]} page_size={@page_sizes["jobs"]} selected_job_ids={@selected_job_ids} read_only={@read_only} />
                    <% "monitor" -> %>
                      <.monitor monitor_server_info={@monitor_server_info} monitor_cache_info={@monitor_cache_info} online_user_rows={@online_user_rows} online_user_total={@online_user_total} online_user_page_num={@page_nums["online-users"]} online_user_page_size={@page_sizes["online-users"]} network_status={@network_status} monitor_help_open={@monitor_help_open} security_access={@security_access} security_metrics={@security_metrics} security_api_keys={@security_api_keys} security_event_rows={@security_event_rows} security_event_total={@security_event_total} monitor_feedback={@monitor_feedback} read_only={@read_only} />
                    <% "profile" -> %>
                      <.profile profile_form={@profile_form} password_form={@password_form} profile_feedback={@profile_feedback} avatar_upload={@uploads.avatar} />
                    <% _ -> %>
                      <div class="panel"><p>请选择一个管理模块。</p></div>
                  <% end %>
                  </div>
                <% else %>
                  <nav class="module-nav" aria-label="个人模块">
                  </nav>
                  <div class="page-content">
                  <%= if @active_panel == "profile" do %>
                    <.profile profile_form={@profile_form} password_form={@password_form} profile_feedback={@profile_feedback} avatar_upload={@uploads.avatar} />
                  <% else %>
                    <div class="card">
                      <h2>登录成功</h2>
                      <p class="muted">当前账号没有管理后台权限。</p>
                      <button type="button" class="secondary" phx-click="show-panel" aria-current={if @active_panel == "profile", do: "page"} phx-value-panel="profile">打开个人资料</button>
                    </div>
                  <% end %>
                  </div>
                <% end %>
              </div>
            <% else %>
              <div class="login-glow login-glow-one" aria-hidden="true"></div>
              <div class="login-glow login-glow-two" aria-hidden="true"></div>
              <div class="login-layout">
              <section class="login-intro">
                <div class="brand-mark" aria-hidden="true"><svg xmlns="http://www.w3.org/2000/svg" width="19" height="19" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="M22 12h-4l-3 9L9 3l-3 9H2" /></svg></div>
                <p class="eyebrow">KEYSTONE / ADMIN</p>
                <h1>把平台状态，<span>放在一个清晰的工作台。</span></h1>
                <p class="login-lede">从登录、授权到运行监控，管理前端只保留完成运维判断所需的证据。</p>
                <div class="login-signals" aria-label="平台能力">
                  <div><strong>30s</strong><span>健康快照刷新</span></div>
                  <div><strong>99.9%</strong><span>系统 API 可用目标</span></div>
                </div>
              </section>
              <div class="card login-card">
                <div class="login-card-header">
                  <div class="brand-mark brand-mark-small" aria-hidden="true"><svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M22 12h-4l-3 9L9 3l-3 9H2" /></svg></div>
                  <div><p class="eyebrow">安全登录</p><h2>进入管理台</h2></div>
                </div>
                <%= if @mfa_challenge do %>
                  <form id="mfa-login-form" class="login-form" phx-submit="verify-login-mfa">
                    <h2>完成二次认证</h2>
                    <p class="muted">账号：<%= @mfa_username %></p>
                    <label for="mfa-code">MFA 验证码</label>
                    <input id="mfa-code" name="code" inputmode="numeric" autocomplete="one-time-code" required />
                    <p :if={@mfa_error} class="error" role="alert"><%= @mfa_error %></p>
                    <button type="submit" phx-disable-with="验证中…">验证并登录</button>
                    <button type="button" class="secondary" phx-click="cancel-login-mfa">返回登录</button>
                  </form>
                <% else %>
                  <form id="login-form" class="login-form" phx-submit="login">
                    <label for="username">用户名</label>
                    <div class="input-wrap"><svg xmlns="http://www.w3.org/2000/svg" width="17" height="17" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><circle cx="12" cy="8" r="4" /><path d="M4 21a8 8 0 0 1 16 0" /></svg><input id="username" name="username" value={@username} autocomplete="username" required /></div>
                    <label for="password">密码</label>
                    <div class="input-wrap"><svg xmlns="http://www.w3.org/2000/svg" width="17" height="17" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><rect x="4" y="10" width="16" height="10" rx="2" /><path d="M8 10V7a4 4 0 0 1 8 0v3" /><path d="M12 14v2" /></svg><input id="password" name="password" type="password" autocomplete="current-password" required /></div>
                    <div :if={@captcha_enabled}>
                      <label for="captcha-code">验证码</label>
                      <img :if={@captcha_image} src={"data:image/gif;base64," <> @captcha_image} alt="登录验证码" width="160" height="60" />
                      <button type="button" class="secondary" phx-click="refresh-captcha">刷新验证码</button>
                      <input id="captcha-code" name="captchaCode" value="" autocomplete="off" required />
                    </div>
                    <%= if @login_error do %><p class="error" role="alert"><%= @login_error %></p><% end %>
                    <button type="submit" class="login-submit" phx-disable-with="登录中…">登录 <svg xmlns="http://www.w3.org/2000/svg" width="17" height="17" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M5 12h14" /><path d="m13 6 6 6-6 6" /></svg></button>
                  </form>
                <% end %>
                <p class="login-footnote"><svg xmlns="http://www.w3.org/2000/svg" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><circle cx="7.5" cy="15.5" r="3.5" /><path d="m10 13 9-9 2 2-2 2 2 2-3 3-2-2-4 4" /></svg>访问令牌只保存在当前页面内存，页面刷新后需要重新登录。</p>
              </div>
              </div>
            <% end %>
          </section>
        </main>
        <script src="/assets/phoenix/phoenix.min.js"></script>
        <script src="/assets/phoenix_live_view/phoenix_live_view.min.js"></script>
        <script src="/js/live_socket.js"></script>
      </body>
    </html>
    """
  end
end
