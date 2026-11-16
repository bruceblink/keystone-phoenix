defmodule KeystonePhoenixWeb.LoginLive do
  use Phoenix.LiveView
  import Phoenix.Component
  import KeystonePhoenixWeb.Live.AdminPages.Accounts
  import KeystonePhoenixWeb.Live.AdminPages.ApiKeys
  import KeystonePhoenixWeb.Live.AdminPages.Operations
  import KeystonePhoenixWeb.Live.AdminPages.Notifications
  import KeystonePhoenixWeb.Live.AdminPages.LoginConfirmation
  import KeystonePhoenixWeb.Live.AdminPages.Organization
  import KeystonePhoenixWeb.Live.AdminPages.System
  import KeystonePhoenixWeb.Live.AdminPages.Navigation, only: [nav_icon: 1]

  alias KeystonePhoenix.Auth
  alias KeystonePhoenix.Auth.LoginLimiter
  alias KeystonePhoenixWeb.Live.AdminSupport
  alias KeystonePhoenixWeb.Live.AdminPages.Feedback
  alias KeystonePhoenixWeb.Live.AdminPages.Navigation
  alias KeystonePhoenixWeb.Live.AdminPages.FilterNavigation
  alias KeystonePhoenixWeb.Live.Authentication
  alias KeystonePhoenixWeb.Live.LoginState
  alias KeystonePhoenixWeb.LoginNotifications
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
  def handle_params(params, uri, socket) do
    requested_panel = Navigation.panel_for_path(uri)
    socket = assign(socket, current_uri: uri)

    if AdminSupport.authenticated_socket?(socket) do
      socket = assign(socket, active_panel: requested_panel)
      socket = assign(socket, FilterNavigation.assigns(requested_panel, params))
      socket = FilterNavigation.apply_page(socket, requested_panel, params)
      OperationsEvents.restore_selected_job_if_needed(socket, requested_panel)
    else
      {:noreply, assign(socket, requested_panel: requested_panel)}
    end
  end

  def handle_event("login", params, socket),
    do: LoginEvents.handle_login(params, socket, liveview_ip(socket))

  def handle_event("force-login", params, socket),
    do: LoginEvents.handle_force_login(params, socket)

  def handle_event("cancel-force-login", _params, socket),
    do:
      {:noreply,
       assign(socket,
         login_confirm_open: false,
         pending_login: nil,
         pending_mfa_login: false
       )}

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
  def handle_event("toggle-notifications", _params, socket), do: LoginNotifications.toggle(socket)

  def handle_event("retry-notifications", _params, socket), do: LoginNotifications.retry(socket)

  def handle_event("close-notifications", _params, socket), do: LoginNotifications.close(socket)

  def handle_event("back-notifications", _params, socket), do: LoginNotifications.back(socket)

  def handle_event("open-notification", params, socket),
    do: LoginNotifications.open(params, socket)

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
          {:noreply, assign(socket, active_panel: panel, log_feedback: nil)}

        panel == "api-keys" ->
          SecurityEvents.handle_event(
            "refresh-api-keys",
            %{},
            assign(socket, active_panel: panel, issued_api_key: nil)
          )

        panel == "notices" ->
          SystemEvents.handle_event("refresh-notices", %{}, assign(socket, active_panel: panel))

        panel == "jobs" ->
          OperationsEvents.handle_event("refresh-jobs", %{}, assign(socket, active_panel: panel))

        panel == "users" ->
          AccountsEvents.handle_event(
            "filter-users",
            %{
              "username" => socket.assigns[:user_query],
              "displayName" => socket.assigns[:user_display_name_query]
            },
            assign(socket, active_panel: panel)
          )

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
             "roles",
             "jobs",
             "job-logs",
             "configs",
             "api-keys",
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
        dispatch_pagination(panel, page, socket)

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("paginate", _params, socket), do: {:noreply, socket}

  @organization_events ~w(refresh-depts new-dept edit-dept save-dept toggle-dept-status delete-dept refresh-posts paginate-posts export-posts new-post edit-post save-post toggle-post-status delete-post refresh-roles paginate-roles export-roles new-role edit-role filter-role-permissions toggle-role-permission save-role toggle-role-selection toggle-all-role-selection toggle-role-status delete-role select-role assign-role-user unassign-role-user refresh-menus new-menu edit-menu save-menu toggle-menu-status delete-menu)
  @accounts_events ~w(filter-users reset-user-filter refresh-users paginate-users export-users new-user-import toggle-user-selection toggle-all-user-selection delete-users import-users new-user edit-user save-user toggle-user-status delete-user reset-user-password save-profile change-profile-password update-profile-avatar save-profile-avatar-upload)
  @config_events ~w(refresh-config delete-config filter-configs reset-config-filter paginate-configs new-config edit-config save-config)
  @system_events ~w(refresh-dicts select-dict-type filter-dict-data reset-dict-data-filter paginate-dict-data new-dict-type edit-dict-type save-dict-type delete-dict-type new-dict-data edit-dict-data save-dict-data delete-dict-data refresh-logs refresh-login-logs refresh-operation-logs new-notice edit-notice cancel-notice save-notice toggle-notice-status publish-notice toggle-notice-selection toggle-all-notice-selection paginate-notices delete-notice delete-notices refresh-notices filter-notices reset-notice-filter)
  @audit_events ~w(filter-login-logs reset-login-log-filter paginate-login-logs filter-operation-logs reset-operation-log-filter paginate-operation-logs filter-dict-types reset-dict-type-filter export-login-logs export-operation-logs)
  @operations_events ~w(refresh-jobs filter-jobs reset-job-filter toggle-job-selection toggle-all-job-selection select-job new-job edit-job save-job delete-job delete-jobs run-job cancel-job toggle-job-status refresh-job-logs refresh-monitor toggle-monitor-help logout-online-user)
  @security_events ~w(refresh-api-keys new-api-key save-api-key rotate-api-key revoke-api-key filter-api-keys paginate-api-keys filter-api-key-scopes toggle-api-key-scope dismiss-api-key-secret)

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

  def handle_event("logout", _params, socket) do
    Auth.logout(socket.assigns.refresh_token)
    {:noreply, socket |> LoginState.reset() |> Authentication.refresh_captcha()}
  end

  def handle_event(_event, _params, socket), do: {:noreply, socket}

  defp dispatch_pagination("posts", page, socket),
    do: OrganizationEvents.handle_event("paginate-posts", %{"page" => page}, socket)

  defp dispatch_pagination("users", page, socket),
    do: AccountsEvents.handle_event("paginate-users", %{"page" => page}, socket)

  defp dispatch_pagination("roles", page, socket),
    do: OrganizationEvents.handle_event("paginate-roles", %{"page" => page}, socket)

  defp dispatch_pagination("configs", page, socket),
    do: ConfigEvents.handle_event("paginate-configs", %{"page" => page}, socket)

  defp dispatch_pagination("api-keys", page, socket),
    do: SecurityEvents.handle_event("paginate-api-keys", %{"page" => page}, socket)

  defp dispatch_pagination("dict-data", page, socket),
    do: SystemEvents.handle_event("paginate-dict-data", %{"page" => page}, socket)

  defp dispatch_pagination("jobs", page, socket),
    do: OperationsEvents.handle_event("paginate-jobs", %{"page" => page}, socket)

  defp dispatch_pagination("job-logs", page, socket),
    do: OperationsEvents.handle_event("paginate-job-logs", %{"page" => page}, socket)

  defp dispatch_pagination("login-logs", page, socket),
    do: AuditEvents.handle_event("paginate-login-logs", %{"page" => page}, socket)

  defp dispatch_pagination("operation-logs", page, socket),
    do: AuditEvents.handle_event("paginate-operation-logs", %{"page" => page}, socket)

  defp dispatch_pagination("online-users", _page, socket) do
    if AdminSupport.panel_allowed?(socket, "monitor"),
      do: {:noreply, AdminSupport.assign_monitor(socket)},
      else: {:noreply, socket}
  end

  defp dispatch_pagination(_panel, _page, socket), do: {:noreply, socket}

  @impl true
  def handle_async(name, result, socket),
    do: LoginNotifications.handle_async(name, result, socket)

  @impl true
  def handle_info({:admin_job_finished, _job_id, result}, socket) do
    feedback =
      case result do
        :ok ->
          "任务已执行并写入运行日志"

        {:skipped, :already_running} ->
          "任务正在执行，本次触发已跳过"

        {:error, :not_found} ->
          Feedback.error(:resource_not_found, "找不到指定任务")

        {:error, reason} ->
          Feedback.error(
            Feedback.code(Feedback.from_reason(reason)),
            "任务执行失败：#{inspect(reason)}"
          )

        _ ->
          Feedback.error(:internal_error, "任务状态未知，请检查运行日志")
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
          <section class={if @current_user, do: "app-shell", else: "login-page"}>
            <%= if @current_user do %>
              <aside class={"sidebar#{if @sidebar_open, do: " sidebar-open", else: ""}"}>
                <div class="sidebar-head">
                  <div class="brand-mark" aria-hidden="true"><svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="M22 12h-4l-3 9L9 3l-3 9H2" /></svg></div>
                  <div><strong>KEYSTONE</strong><span>Admin Console</span></div>
                  <button type="button" class="mobile-close" phx-click="close-sidebar" aria-label="关闭导航"><svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M18 6 6 18M6 6l12 12" /></svg></button>
                </div>
                <%= if Enum.any?(Map.values(@panel_access)) do %>
                  <nav class={"primary-nav#{if @sidebar_open, do: " sidebar-open", else: ""}"} aria-label="主导航">
                    <button :if={@panel_access["monitor"]} type="button" class={if @active_panel == "monitor", do: "nav-item nav-item-active", else: "nav-item"} phx-click="show-panel" aria-current={if @active_panel == "monitor", do: "page"} phx-value-panel="monitor"><span class="nav-icon" aria-hidden="true"><.nav_icon name="activity" /></span><span>运行监控</span></button>
                    <button :if={@panel_access["users"]} type="button" class={if @active_panel == "users", do: "nav-item nav-item-active", else: "nav-item"} phx-click="show-panel" aria-current={if @active_panel == "users", do: "page"} phx-value-panel="users"><span class="nav-icon" aria-hidden="true"><.nav_icon name="users" /></span><span>用户与权限</span></button>
                    <button :if={@panel_access["roles"]} type="button" class={if @active_panel == "roles", do: "nav-item nav-item-active", else: "nav-item"} phx-click="show-panel" aria-current={if @active_panel == "roles", do: "page"} phx-value-panel="roles"><span class="nav-icon" aria-hidden="true"><.nav_icon name="user-cog" /></span><span>角色管理</span></button>
                    <button :if={@panel_access["depts"]} type="button" class={if @active_panel == "depts", do: "nav-item nav-item-active", else: "nav-item"} phx-click="show-panel" aria-current={if @active_panel == "depts", do: "page"} phx-value-panel="depts"><span class="nav-icon" aria-hidden="true"><.nav_icon name="building" /></span><span>组织结构</span></button>
                    <button :if={@panel_access["posts"]} type="button" class={if @active_panel == "posts", do: "nav-item nav-item-active", else: "nav-item"} phx-click="show-panel" aria-current={if @active_panel == "posts", do: "page"} phx-value-panel="posts"><span class="nav-icon" aria-hidden="true"><.nav_icon name="briefcase" /></span><span>岗位管理</span></button>
                    <button :if={@panel_access["menus"]} type="button" class={if @active_panel == "menus", do: "nav-item nav-item-active", else: "nav-item"} phx-click="show-panel" aria-current={if @active_panel == "menus", do: "page"} phx-value-panel="menus"><span class="nav-icon" aria-hidden="true"><.nav_icon name="list-tree" /></span><span>菜单与权限</span></button>
                    <button :if={@panel_access["api-keys"]} type="button" class={if @active_panel == "api-keys", do: "nav-item nav-item-active", else: "nav-item"} phx-click="show-panel" aria-current={if @active_panel == "api-keys", do: "page"} phx-value-panel="api-keys"><span class="nav-icon" aria-hidden="true"><.nav_icon name="key" /></span><span>API Key</span></button>
                    <a class="nav-item" href="/api/swagger" target="_blank" rel="noreferrer" phx-click="close-sidebar"><span class="nav-icon" aria-hidden="true"><.nav_icon name="file-text" /></span><span>接口文档</span></a>
                    <span class="nav-section-title nav-label nav-label-spaced">运维审计</span>
                    <button :if={@panel_access["operation-logs"]} type="button" class={if @active_panel == "operation-logs", do: "nav-item nav-item-active", else: "nav-item"} phx-click="show-panel" aria-current={if @active_panel == "operation-logs", do: "page"} phx-value-panel="operation-logs"><span class="nav-icon" aria-hidden="true"><.nav_icon name="shield" /></span><span>操作审计</span></button>
                    <button :if={@panel_access["login-logs"]} type="button" class={if @active_panel == "login-logs", do: "nav-item nav-item-active", else: "nav-item"} phx-click="show-panel" aria-current={if @active_panel == "login-logs", do: "page"} phx-value-panel="login-logs"><span class="nav-icon" aria-hidden="true"><.nav_icon name="file-clock" /></span><span>登录日志</span></button>
                    <button :if={@panel_access["jobs"]} type="button" class={if @active_panel == "jobs", do: "nav-item nav-item-active", else: "nav-item"} phx-click="show-panel" aria-current={if @active_panel == "jobs", do: "page"} phx-value-panel="jobs"><span class="nav-icon" aria-hidden="true"><.nav_icon name="list-checks" /></span><span>定时任务</span></button>
                    <button :if={@panel_access["configs"]} type="button" class={if @active_panel == "configs", do: "nav-item nav-item-active", else: "nav-item"} phx-click="show-panel" aria-current={if @active_panel == "configs", do: "page"} phx-value-panel="configs"><span class="nav-icon" aria-hidden="true"><.nav_icon name="settings" /></span><span>系统配置</span></button>
                    <button :if={@panel_access["dicts"]} type="button" class={if @active_panel == "dicts", do: "nav-item nav-item-active", else: "nav-item"} phx-click="show-panel" aria-current={if @active_panel == "dicts", do: "page"} phx-value-panel="dicts"><span class="nav-icon" aria-hidden="true"><.nav_icon name="book-open" /></span><span>字典管理</span></button>
                    <button :if={@panel_access["notices"]} type="button" class={if @active_panel == "notices", do: "nav-item nav-item-active", else: "nav-item"} phx-click="show-panel" aria-current={if @active_panel == "notices", do: "page"} phx-value-panel="notices"><span class="nav-icon" aria-hidden="true"><.nav_icon name="megaphone" /></span><span>通知公告</span></button>
                  </nav>
                <% else %>
                  <nav class="primary-nav" aria-label="个人模块"></nav>
                <% end %>
                <div class="sidebar-foot"><div class="status-dot"><span></span> API 正常</div><span class="sidebar-version">v0.1.0 · dev</span></div>
              </aside>
              <button :if={@sidebar_open} type="button" class="sidebar-scrim" phx-click="toggle-sidebar" aria-label="关闭导航"></button>
              <div class="shell-content">
                <header class="topbar">
                  <button type="button" class="mobile-menu" phx-click="toggle-sidebar" aria-label={if @sidebar_open, do: "关闭导航", else: "打开导航"} aria-expanded={@sidebar_open}><svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M4 6h16M4 12h16M4 18h16" /></svg></button>
                  <div class="topbar-context">
                    <span class="context-kicker">Keystone</span><span class="context-separator">/</span>
                  </div>
                  <div class="topbar-actions">
                    <.menu open={@notifications_open} loading={@notifications_loading} notifications={@in_app_notifications} error={@notifications_error} selected={LoginNotifications.selected(@in_app_notifications, @selected_notification_id)} />
                    <button type="button" class="user-menu user-menu-button user-profile-button" phx-click="show-panel" phx-value-panel="profile" aria-label="打开个人资料">
                      <span class="avatar user-avatar" aria-hidden="true"><%= String.first(to_string(@current_user["nickname"] || @current_user["username"])) %></span>
                      <span class="user-copy">
                        <strong><%= @current_user["nickname"] || @current_user["username"] %></strong>
                        <span><%= @current_user["role"] || @current_user["roleName"] || "管理员" %></span>
                      </span>
                      <svg class="profile-chevron" xmlns="http://www.w3.org/2000/svg" width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="m6 9 6 6 6-6" /></svg>
                    </button>
                    <button type="button" class="button button-ghost logout-button" phx-click="logout" phx-disable-with="退出中…"><svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4" /><path d="m16 17 5-5-5-5" /><path d="M21 12H9" /></svg><span>退出</span></button>
                  </div>
                </header>
                <main class="shell-main">
                  <p :if={@mfa_step_up_notice} id="mfa-step-up-notice" class="notice" role="status"><%= @mfa_step_up_notice %></p>
                  <div :if={@mfa_step_up_required} id="mfa-step-up-panel" class="card" role="alert">
                    <h3>需要二次认证</h3>
                    <p :if={@mfa_step_up_error} class="error"><%= @mfa_step_up_error %></p>
                    <%= if @mfa_step_up_challenge do %>
                      <form id="mfa-step-up-form" phx-submit="verify-liveview-step-up">
                        <label for="mfa-step-up-code">一次性验证码</label>
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
                  <%= case @active_panel do %>
                    <% "depts" -> %>
                      <.departments dept_rows={@dept_rows} dept_form={@dept_form} dept_feedback={@dept_feedback} dept_filter={@dept_filter} active_modal={@active_modal} read_only={@read_only} permissions={@permissions} />
                    <% "posts" -> %>
                      <.posts post_rows={@post_rows} post_total={@post_total} post_form={@post_form} post_feedback={@post_feedback} post_filter={@post_filter} active_modal={@active_modal} page_num={@page_nums["posts"]} page_size={@page_sizes["posts"]} read_only={@read_only} permissions={@permissions} />
                    <% "roles" -> %>
                      <.roles role_rows={@role_rows} role_page_rows={@role_page_rows} role_total={@role_total} role_form={@role_form} role_feedback={@role_feedback} role_filter={@role_filter} menu_rows={@menu_rows} active_modal={@active_modal} selected_role_ids={@selected_role_ids} selected_role_id={@selected_role_id} selected_role_name={@selected_role_name} allocated_role_user_rows={@allocated_role_user_rows} unallocated_role_user_rows={@unallocated_role_user_rows} role_user_feedback={@role_user_feedback} allocated_page_num={@page_nums["role-users-allocated"]} unallocated_page_num={@page_nums["role-users-unallocated"]} role_user_page_size={@page_sizes["role-users-allocated"]} page_num={@page_nums["roles"]} page_size={@page_sizes["roles"]} read_only={@read_only} permissions={@permissions} />
                    <% "menus" -> %>
                      <.menus menu_rows={@menu_rows} menu_form={@menu_form} menu_feedback={@menu_feedback} menu_filter={@menu_filter} menu_role_codes={@menu_role_codes} role_rows={@role_rows} permissions={@permissions} active_modal={@active_modal} read_only={@read_only} />
                    <% "users" -> %>
                      <.users user_rows={@user_rows} user_total={@user_total} users_server_paged={@users_server_paged} user_form={@user_form} user_feedback={@user_feedback} user_query={@user_query} user_display_name_query={@user_display_name_query} selected_user_ids={@selected_user_ids} user_import_result={@user_import_result} active_modal={@active_modal} dept_rows={@dept_rows} post_rows={@post_rows} role_rows={@role_rows} page_num={@page_nums["users"]} page_size={@page_sizes["users"]} read_only={@read_only} permissions={@permissions} user_import_upload={@uploads.user_import} />
                    <% "api-keys" -> %>
                      <.api_keys api_key_rows={@api_key_rows} api_key_total={@api_key_total} api_key_page_num={@page_nums["api-keys"]} api_key_page_size={@page_sizes["api-keys"]} api_key_feedback={@api_key_feedback} api_key_form={@api_key_form} api_key_query={@api_key_query} api_key_status={@api_key_status} issued_api_key={@issued_api_key} permissions={@permissions} active_modal={@active_modal} read_only={@read_only} />
                    <% "configs" -> %>
                      <.configs config_rows={@config_rows} config_total={@config_total} config_page_num={@page_nums["configs"]} config_page_size={@page_sizes["configs"]} config_form={@config_form} config_feedback={@config_feedback} config_filter={@config_filter} active_modal={@active_modal} read_only={@read_only} />
                    <% "dicts" -> %>
                      <.dicts dict_type_rows={@dict_type_rows} dict_data_rows={@dict_data_rows} dict_data_total={@dict_data_total} dict_type_form={@dict_type_form} dict_data_form={@dict_data_form} selected_dict_type={@selected_dict_type} dict_feedback={@dict_feedback} active_modal={@active_modal} dict_data_page_num={@page_nums["dict-data"]} dict_data_page_size={@page_sizes["dict-data"]} dict_type_filter={@dict_type_filter} read_only={@read_only} />
                    <% "notices" -> %>
                      <.notices notice_rows={@notice_rows} notice_total={@notice_total} notice_page_num={@page_nums["notices"]} notice_page_size={@page_sizes["notices"]} notice_form={@notice_form} notice_feedback={@notice_feedback} active_modal={@active_modal} selected_notice_ids={@selected_notice_ids} notice_filter={@notice_filter} read_only={@read_only} />
                    <% "login-logs" -> %>
                      <.logs kind="login" login_log_rows={@login_log_rows} login_log_total={@login_log_total} operation_log_rows={@operation_log_rows} operation_log_total={@operation_log_total} log_feedback={@log_feedback} login_log_filter={@login_log_filter} operation_log_filter={@operation_log_filter} login_page_num={@page_nums["login-logs"]} operation_page_num={@page_nums["operation-logs"]} page_size={@page_sizes["login-logs"]} read_only={@read_only} />
                    <% "operation-logs" -> %>
                      <.logs kind="operation" login_log_rows={@login_log_rows} login_log_total={@login_log_total} operation_log_rows={@operation_log_rows} operation_log_total={@operation_log_total} log_feedback={@log_feedback} login_log_filter={@login_log_filter} operation_log_filter={@operation_log_filter} login_page_num={@page_nums["login-logs"]} operation_page_num={@page_nums["operation-logs"]} page_size={@page_sizes["operation-logs"]} read_only={@read_only} />
                    <% "jobs" -> %>
                      <.jobs job_rows={@job_rows} job_total={@job_total} job_form={@job_form} job_targets={@job_targets} job_feedback={@job_feedback} job_filter={@job_filter} active_modal={@active_modal} page_num={@page_nums["jobs"]} page_size={@page_sizes["jobs"]} selected_job_ids={@selected_job_ids} selected_job_id={@selected_job_id} selected_job={@selected_job} job_log_rows={@job_log_rows} job_log_total={@job_log_total} job_log_page_num={@page_nums["job-logs"]} job_log_page_size={@page_sizes["job-logs"]} read_only={@read_only} />
                    <% "monitor" -> %>
                      <.monitor monitor_server_info={@monitor_server_info} monitor_cache_info={@monitor_cache_info} online_user_rows={@online_user_rows} online_user_total={@online_user_total} online_user_page_num={@page_nums["online-users"]} online_user_page_size={@page_sizes["online-users"]} network_status={@network_status} monitor_help_open={@monitor_help_open} security_access={@security_access} security_metrics={@security_metrics} security_api_keys={@security_api_keys} security_event_rows={@security_event_rows} security_event_total={@security_event_total} monitor_feedback={@monitor_feedback} read_only={@read_only} />
                    <% "profile" -> %>
                      <.profile profile_form={@profile_form} password_form={@password_form} profile_feedback={@profile_feedback} />
                    <% _ -> %>
                      <div class="panel"><p>请选择一个管理模块。</p></div>
                  <% end %>
                  <% else %>
                    <%= if @active_panel == "profile" do %>
                      <.profile profile_form={@profile_form} password_form={@password_form} profile_feedback={@profile_feedback} />
                    <% else %>
                      <div class="card">
                        <h2>登录成功</h2>
                        <p class="muted">当前账号没有管理后台权限。</p>
                        <button type="button" class="secondary" phx-click="show-panel" aria-current={if @active_panel == "profile", do: "page"} phx-value-panel="profile">打开个人资料</button>
                      </div>
                    <% end %>
                  <% end %>
                </main>
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
                    <p class="form-status" role="status">账号密码已验证，请输入认证器中的一次性验证码。</p>
                    <label for="mfa-code">一次性验证码</label>
                    <div class="input-wrap"><svg xmlns="http://www.w3.org/2000/svg" width="17" height="17" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M15 7a5 5 0 1 0 2 9.6L21 13l-2-2 2-2-2-2-2 2-2-2Z" /><circle cx="10" cy="12" r="1" /></svg><input id="mfa-code" name="code" inputmode="numeric" autocomplete="one-time-code" required /></div>
                    <p :if={@mfa_error} class="form-error" role="alert"><%= @mfa_error %></p>
                    <button type="submit" class="login-submit" phx-disable-with="验证中…">验证并登录 <svg xmlns="http://www.w3.org/2000/svg" width="17" height="17" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M5 12h14" /><path d="m13 6 6 6-6 6" /></svg></button>
                    <button type="button" class="button button-ghost button-sm" phx-click="cancel-login-mfa">返回账号密码</button>
                  </form>
                <% else %>
                  <form id="login-form" class="login-form" phx-submit="login">
                    <label for="username">用户名</label>
                    <div class="input-wrap"><svg xmlns="http://www.w3.org/2000/svg" width="17" height="17" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><circle cx="12" cy="8" r="4" /><path d="M4 21a8 8 0 0 1 16 0" /></svg><input id="username" name="username" value={@username} autocomplete="username" required /></div>
                    <label for="password">密码</label>
                    <div class="input-wrap"><svg xmlns="http://www.w3.org/2000/svg" width="17" height="17" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><rect x="4" y="10" width="16" height="10" rx="2" /><path d="M8 10V7a4 4 0 0 1 8 0v3" /><path d="M12 14v2" /></svg><input id="password" name="password" type="password" value={@password} autocomplete="current-password" required /></div>
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
              <.modal open={@login_confirm_open} />
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
