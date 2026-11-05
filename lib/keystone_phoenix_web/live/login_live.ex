defmodule KeystonePhoenixWeb.LoginLive do
  use Phoenix.LiveView

  import Phoenix.Component
  import KeystonePhoenixWeb.Live.AdminPages.Accounts
  import KeystonePhoenixWeb.Live.AdminPages.Operations
  import KeystonePhoenixWeb.Live.AdminPages.Organization
  import KeystonePhoenixWeb.Live.AdminPages.System

  alias KeystonePhoenix.Auth
  alias KeystonePhoenix.Job
  alias KeystonePhoenixWeb.Live.AdminSupport
  alias KeystonePhoenixWeb.Live.AdminEvents.Accounts, as: AccountsEvents
  alias KeystonePhoenixWeb.Live.AdminEvents.Operations, as: OperationsEvents
  alias KeystonePhoenixWeb.Live.AdminEvents.Organization, as: OrganizationEvents
  alias KeystonePhoenixWeb.Live.AdminEvents.System, as: SystemEvents

  @impl true
  def mount(_params, _session, socket) do
    socket =
      allow_upload(socket, :avatar,
        accept: ~w(.bmp .gif .jpg .jpeg .png .webp),
        max_entries: 1,
        max_file_size: 50 * 1024 * 1024
      )

    {:ok,
     assign(socket,
       username: "",
       password: "",
       login_error: nil,
       current_user: nil,
       access_token: nil,
       refresh_token: nil,
       active_panel: "overview",
       user_rows: [],
       dept_rows: [],
       dept_feedback: nil,
       dept_form: empty_dept_form(),
       post_rows: [],
       post_feedback: nil,
       post_form: empty_post_form(),
       config_rows: [],
       config_feedback: nil,
       config_form: empty_config_form(),
       dict_type_rows: [],
       dict_data_rows: [],
       dict_feedback: nil,
       dict_type_form: empty_dict_type_form(),
       dict_data_form: empty_dict_data_form(),
       selected_dict_type: "",
       job_rows: [],
       job_feedback: nil,
       job_form: empty_job_form(),
       job_targets: Job.invoke_targets(),
       job_log_rows: [],
       job_log_feedback: nil,
       role_rows: [],
       selected_role_id: "",
       selected_role_name: "",
       allocated_role_user_rows: [],
       unallocated_role_user_rows: [],
       role_user_feedback: nil,
       role_feedback: nil,
       role_form: empty_role_form(),
       menu_rows: [],
       menu_feedback: nil,
       menu_form: empty_menu_form(),
       notice_rows: [],
       notice_feedback: nil,
       notice_form: empty_notice_form(),
       login_log_rows: [],
       operation_log_rows: [],
       log_feedback: nil,
       user_form: empty_user_form(),
       user_feedback: nil,
       profile_form: empty_profile_form(),
       password_form: empty_password_form(),
       profile_feedback: nil,
       monitor_server_info: %{},
       monitor_cache_info: %{},
       online_user_rows: [],
       network_status: %{},
       monitor_feedback: nil
     )}
  end

  @impl true
  def handle_event("login", %{"username" => username, "password" => password}, socket) do
    username = String.trim(username)

    case Auth.login_plaintext(username, password) do
      {:ok, tokens} ->
        dashboard =
          if tokens.current_user["isAdmin"] == 1 do
            load_dashboard()
          else
            empty_dashboard()
          end

        {:noreply,
         assign(socket,
           username: username,
           password: "",
           login_error: nil,
           current_user: tokens.current_user,
           access_token: tokens.token,
           refresh_token: tokens.refresh_token,
           active_panel: "overview",
           user_rows: dashboard.user_rows,
           dept_rows: dashboard.dept_rows,
           dept_feedback: nil,
           dept_form: empty_dept_form(),
           post_rows: dashboard.post_rows,
           post_feedback: nil,
           post_form: empty_post_form(),
           config_rows: dashboard.config_rows,
           config_feedback: nil,
           config_form: empty_config_form(),
           dict_type_rows: dashboard.dict_type_rows,
           dict_data_rows: dashboard.dict_data_rows,
           dict_feedback: nil,
           dict_type_form: empty_dict_type_form(),
           dict_data_form: empty_dict_data_form(dashboard.selected_dict_type),
           selected_dict_type: dashboard.selected_dict_type,
           job_rows: dashboard.job_rows,
           job_feedback: nil,
           job_form: empty_job_form(),
           job_targets: Job.invoke_targets(),
           job_log_rows: dashboard.job_log_rows,
           job_log_feedback: nil,
           role_rows: dashboard.role_rows,
           selected_role_id: "",
           selected_role_name: "",
           allocated_role_user_rows: [],
           unallocated_role_user_rows: [],
           role_user_feedback: nil,
           role_feedback: nil,
           role_form: empty_role_form(),
           menu_rows: dashboard.menu_rows,
           menu_feedback: nil,
           menu_form: empty_menu_form(),
           notice_rows: dashboard.notice_rows,
           notice_feedback: nil,
           notice_form: empty_notice_form(),
           login_log_rows: dashboard.login_log_rows,
           operation_log_rows: dashboard.operation_log_rows,
           log_feedback: nil,
           user_form: empty_user_form(),
           user_feedback: nil,
           profile_form: tokens.current_user,
           password_form: empty_password_form(),
           profile_feedback: nil
         )}

      {:error, :already_logged_in} ->
        {:noreply, assign(socket, login_error: "该账号已经登录，请先退出或使用 API 的 forceLogin 接管")}

      {:error, :unavailable} ->
        {:noreply, assign(socket, login_error: "认证会话暂不可用，请稍后重试")}

      _ ->
        {:noreply, assign(socket, login_error: "用户名或密码错误")}
    end
  end

  def handle_event("login", _params, socket) do
    {:noreply, assign(socket, login_error: "请输入用户名和密码")}
  end

  @impl true
  def handle_event("show-panel", %{"panel" => panel}, socket)
      when panel in [
             "overview",
             "depts",
             "posts",
             "roles",
             "menus",
             "notices",
             "logs",
             "users",
             "configs",
             "dicts",
             "jobs",
             "job-logs",
             "profile",
             "monitor"
           ] do
    if admin_socket?(socket) do
      cond do
        panel == "monitor" ->
          {:noreply, assign_monitor(socket)}

        panel == "job-logs" ->
          {:noreply, assign(socket, active_panel: panel, job_log_rows: load_job_logs())}

        panel == "profile" ->
          {:noreply, assign_profile(socket)}

        true ->
          {:noreply, assign(socket, active_panel: panel)}
      end
    else
      if panel == "profile" and authenticated_socket?(socket) do
        {:noreply, assign_profile(socket)}
      else
        {:noreply, socket}
      end
    end
  end

  def handle_event("show-panel", _params, socket), do: {:noreply, socket}

  @organization_events ~w(refresh-depts new-dept edit-dept save-dept toggle-dept-status delete-dept refresh-posts new-post edit-post save-post toggle-post-status delete-post refresh-roles new-role edit-role save-role toggle-role-status delete-role select-role assign-role-user unassign-role-user refresh-menus new-menu edit-menu save-menu toggle-menu-status delete-menu)
  @accounts_events ~w(refresh-users new-user edit-user save-user toggle-user-status delete-user reset-user-password save-profile change-profile-password update-profile-avatar save-profile-avatar-upload)
  @system_events ~w(refresh-config new-config edit-config save-config refresh-dicts select-dict-type new-dict-type edit-dict-type save-dict-type delete-dict-type new-dict-data edit-dict-data save-dict-data delete-dict-data refresh-logs edit-notice cancel-notice save-notice toggle-notice-status delete-notice refresh-notices delete-login-log delete-operation-log)
  @operations_events ~w(refresh-jobs new-job edit-job save-job delete-job run-job cancel-job toggle-job-status refresh-job-logs refresh-monitor logout-online-user)

  @impl true
  def handle_event(event, params, socket) when event in @organization_events,
    do: OrganizationEvents.handle_event(event, params, socket)

  def handle_event(event, params, socket) when event in @accounts_events,
    do: AccountsEvents.handle_event(event, params, socket)

  def handle_event(event, params, socket) when event in @system_events,
    do: SystemEvents.handle_event(event, params, socket)

  def handle_event(event, params, socket) when event in @operations_events,
    do: OperationsEvents.handle_event(event, params, socket)

  @impl true
  def handle_event("logout", _params, socket) do
    Auth.logout(socket.assigns.refresh_token)

    {:noreply,
     assign(socket,
       password: "",
       login_error: nil,
       current_user: nil,
       access_token: nil,
       refresh_token: nil,
       active_panel: "overview",
       user_rows: [],
       dept_rows: [],
       dept_feedback: nil,
       dept_form: empty_dept_form(),
       post_rows: [],
       post_feedback: nil,
       post_form: empty_post_form(),
       config_rows: [],
       config_feedback: nil,
       config_form: empty_config_form(),
       dict_type_rows: [],
       dict_data_rows: [],
       dict_feedback: nil,
       dict_type_form: empty_dict_type_form(),
       dict_data_form: empty_dict_data_form(),
       selected_dict_type: "",
       job_rows: [],
       job_feedback: nil,
       job_form: empty_job_form(),
       job_targets: Job.invoke_targets(),
       job_log_rows: [],
       job_log_feedback: nil,
       role_rows: [],
       selected_role_id: "",
       selected_role_name: "",
       allocated_role_user_rows: [],
       unallocated_role_user_rows: [],
       role_user_feedback: nil,
       role_feedback: nil,
       role_form: empty_role_form(),
       menu_rows: [],
       menu_feedback: nil,
       menu_form: empty_menu_form(),
       notice_rows: [],
       notice_feedback: nil,
       notice_form: empty_notice_form(),
       login_log_rows: [],
       operation_log_rows: [],
       log_feedback: nil,
       user_form: empty_user_form(),
       user_feedback: nil,
       profile_form: empty_profile_form(),
       password_form: empty_password_form(),
       profile_feedback: nil,
       monitor_server_info: %{},
       monitor_cache_info: %{},
       online_user_rows: [],
       network_status: %{},
       monitor_feedback: nil
     )}
  end

  defp load_dashboard, do: AdminSupport.load_dashboard()
  defp empty_dashboard, do: AdminSupport.empty_dashboard()
  defp load_job_logs, do: AdminSupport.load_job_logs()
  defp empty_notice_form, do: AdminSupport.empty_notice_form()
  defp empty_dept_form, do: AdminSupport.empty_dept_form()
  defp empty_post_form, do: AdminSupport.empty_post_form()
  defp empty_role_form, do: AdminSupport.empty_role_form()
  defp empty_menu_form, do: AdminSupport.empty_menu_form()
  defp empty_user_form, do: AdminSupport.empty_user_form()
  defp empty_config_form, do: AdminSupport.empty_config_form()
  defp empty_dict_type_form, do: AdminSupport.empty_dict_type_form()
  defp empty_job_form, do: AdminSupport.empty_job_form()
  defp empty_profile_form, do: AdminSupport.empty_profile_form()
  defp empty_password_form, do: AdminSupport.empty_password_form()
  defp empty_dict_data_form(dict_type \\ ""), do: AdminSupport.empty_dict_data_form(dict_type)
  defp assign_monitor(socket, feedback \\ nil), do: AdminSupport.assign_monitor(socket, feedback)
  defp assign_profile(socket), do: AdminSupport.assign_profile(socket)
  defp admin_socket?(socket), do: AdminSupport.admin_socket?(socket)
  defp authenticated_socket?(socket), do: AdminSupport.authenticated_socket?(socket)

  @impl true
  def render(assigns) do
    ~H"""
    <!doctype html>
    <html lang="zh-CN">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <meta name="csrf-token" content={Plug.CSRFProtection.get_csrf_token()} />
        <title>Keystone Phoenix</title>
        <style>
          :root { color-scheme: dark; font-family: Inter, system-ui, sans-serif; }
          body { margin: 0; min-height: 100vh; background: #101827; color: #e5edf7; }
          main { width: min(1200px, calc(100% - 32px)); margin: 0 auto; padding: 48px 0; }
          .shell { display: grid; grid-template-columns: 1.2fr 1fr; gap: 32px; align-items: center; }
          .brand h1 { margin: 0 0 12px; font-size: 42px; letter-spacing: -1px; }
          .brand p { max-width: 520px; color: #9aacbf; line-height: 1.7; }
          .card { padding: 28px; border: 1px solid #27354a; border-radius: 16px; background: #172235; box-shadow: 0 18px 60px #050a1380; }
          label { display: block; margin: 14px 0 6px; color: #a9b9cc; font-size: 14px; }
          input { box-sizing: border-box; width: 100%; padding: 12px 14px; border: 1px solid #3a4c65; border-radius: 8px; background: #0f1828; color: #e5edf7; }
          button { width: 100%; margin-top: 20px; padding: 12px 14px; border: 0; border-radius: 8px; background: #4f8cff; color: white; font-weight: 700; cursor: pointer; }
          button.secondary { background: #31435c; }
          .error { margin: 14px 0 0; color: #ff9b9b; font-size: 14px; }
          .user { display: flex; justify-content: space-between; gap: 12px; align-items: center; }
          .user strong { display: block; font-size: 20px; }
          .user span { color: #9aacbf; }
          .dashboard { grid-column: 1 / -1; }
          .topbar { display: flex; justify-content: space-between; gap: 16px; align-items: center; margin-bottom: 20px; }
          .topbar h2 { margin: 0; }
          nav { display: flex; gap: 8px; flex-wrap: wrap; margin-bottom: 16px; }
          nav button { width: auto; margin: 0; padding: 8px 12px; background: #243650; }
          nav button.active { background: #4f8cff; }
          nav button.danger { background: #8b4a55; }
          .panel { overflow-x: auto; padding: 20px; border: 1px solid #27354a; border-radius: 12px; background: #172235; }
          .panel h3 { margin: 18px 0 10px; }
          .form-grid { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 8px 14px; margin-bottom: 16px; }
          .form-grid .wide { grid-column: 1 / -1; }
          .form-grid input, .form-grid select, .form-grid textarea, select, textarea { box-sizing: border-box; width: 100%; padding: 10px 12px; border: 1px solid #3a4c65; border-radius: 8px; background: #0f1828; color: #e5edf7; }
          .form-grid textarea { min-height: 76px; resize: vertical; }
          .form-actions { display: flex; gap: 8px; flex-wrap: wrap; margin: 10px 0 16px; }
          .form-actions button, table button { width: auto; margin: 0; padding: 8px 12px; }
          .form-actions button.secondary, table button.secondary { background: #31435c; }
          .danger-action { background: #8b4a55 !important; }
          .feedback { margin: 8px 0 14px; color: #9fe2b0; }
          .table-actions { display: flex; gap: 6px; flex-wrap: wrap; }
          .monitor-grid { display: grid; grid-template-columns: repeat(4, minmax(0, 1fr)); gap: 12px; margin: 14px 0 24px; }
          .monitor-grid.details { grid-template-columns: repeat(2, minmax(0, 1fr)); }
          .metric, .details > div { padding: 14px; border: 1px solid #293a52; border-radius: 10px; background: #101827; }
          .metric span, .metric small { display: block; color: #9aacbf; }
          .metric strong { display: block; margin: 8px 0; font-size: 24px; }
          .details h3 { margin-top: 0; }
          .details p { margin: 8px 0; color: #b9c6d6; }
          table { width: 100%; border-collapse: collapse; font-size: 14px; }
          th, td { padding: 10px 8px; border-bottom: 1px solid #293a52; text-align: left; white-space: nowrap; }
          th { color: #9aacbf; font-weight: 600; }
          .muted { color: #9aacbf; }
          .refresh { width: auto; margin: 0 0 14px; padding: 8px 12px; }
          @media (max-width: 720px) {
            .shell { grid-template-columns: 1fr; }
            .monitor-grid, .monitor-grid.details { grid-template-columns: 1fr; }
            main { padding: 32px 0; }
            .brand h1 { font-size: 34px; }
            .form-grid { grid-template-columns: 1fr; }
            .form-grid .wide { grid-column: auto; }
          }
        </style>
      </head>
      <body>
        <main>
          <section class="shell">
            <%= if @current_user do %>
              <div class="dashboard">
                <div class="topbar">
                  <div>
                    <p class="muted">Keystone Phoenix</p>
                    <h2><%= if @current_user["isAdmin"] == 1, do: "管理概览", else: "个人中心" %></h2>
                  </div>
                  <div class="user">
                    <div>
                      <strong><%= @current_user["nickname"] || @current_user["username"] %></strong>
                      <span>@<%= @current_user["username"] %></span>
                    </div>
                    <button type="button" class="secondary" phx-click="logout">退出</button>
                  </div>
                </div>
                <%= if @current_user["isAdmin"] == 1 do %>
                  <nav aria-label="管理模块">
                    <button type="button" class={if @active_panel == "overview", do: "active", else: ""} phx-click="show-panel" phx-value-panel="overview">概览</button>
                    <button type="button" class={if @active_panel == "depts", do: "active", else: ""} phx-click="show-panel" phx-value-panel="depts">部门</button>
                    <button type="button" class={if @active_panel == "posts", do: "active", else: ""} phx-click="show-panel" phx-value-panel="posts">岗位</button>
                    <button type="button" class={if @active_panel == "roles", do: "active", else: ""} phx-click="show-panel" phx-value-panel="roles">角色</button>
                    <button type="button" class={if @active_panel == "menus", do: "active", else: ""} phx-click="show-panel" phx-value-panel="menus">菜单</button>
                    <button type="button" class={if @active_panel == "users", do: "active", else: ""} phx-click="show-panel" phx-value-panel="users">用户</button>
                    <button type="button" class={if @active_panel == "configs", do: "active", else: ""} phx-click="show-panel" phx-value-panel="configs">配置</button>
                    <button type="button" class={if @active_panel == "dicts", do: "active", else: ""} phx-click="show-panel" phx-value-panel="dicts">字典</button>
                    <button type="button" class={if @active_panel == "notices", do: "active", else: ""} phx-click="show-panel" phx-value-panel="notices">公告</button>
                    <button type="button" class={if @active_panel == "logs", do: "active", else: ""} phx-click="show-panel" phx-value-panel="logs">日志</button>
                    <button type="button" class={if @active_panel == "jobs", do: "active", else: ""} phx-click="show-panel" phx-value-panel="jobs">定时任务</button>
                    <button type="button" class={if @active_panel == "job-logs", do: "active", else: ""} phx-click="show-panel" phx-value-panel="job-logs">任务日志</button>
                    <button type="button" class={if @active_panel == "monitor", do: "active", else: ""} phx-click="show-panel" phx-value-panel="monitor">监控</button>
                    <button type="button" class={if @active_panel == "profile", do: "active", else: ""} phx-click="show-panel" phx-value-panel="profile">个人资料</button>
                  </nav>
                  <%= case @active_panel do %>
                    <% "overview" -> %>
                      <div class="panel">
                        <p>当前登录用户：<strong><%= @current_user["username"] %></strong></p>
                        <p class="muted">部门：<%= length(@dept_rows) %>　岗位：<%= length(@post_rows) %>　角色：<%= length(@role_rows) %>　菜单：<%= length(@menu_rows) %>　公告：<%= length(@notice_rows) %>　用户：<%= length(@user_rows) %>　配置：<%= length(@config_rows) %>　字典：<%= length(@dict_type_rows) %>　任务：<%= length(@job_rows) %></p>
                      </div>
                    <% "depts" -> %>
                      <.departments dept_rows={@dept_rows} dept_form={@dept_form} dept_feedback={@dept_feedback} />
                    <% "posts" -> %>
                      <.posts post_rows={@post_rows} post_form={@post_form} post_feedback={@post_feedback} />
                    <% "roles" -> %>
                      <.roles role_rows={@role_rows} role_form={@role_form} role_feedback={@role_feedback} selected_role_id={@selected_role_id} selected_role_name={@selected_role_name} allocated_role_user_rows={@allocated_role_user_rows} unallocated_role_user_rows={@unallocated_role_user_rows} role_user_feedback={@role_user_feedback} />
                    <% "menus" -> %>
                      <.menus menu_rows={@menu_rows} menu_form={@menu_form} menu_feedback={@menu_feedback} />
                    <% "users" -> %>
                      <.users user_rows={@user_rows} user_form={@user_form} user_feedback={@user_feedback} dept_rows={@dept_rows} post_rows={@post_rows} role_rows={@role_rows} />
                    <% "configs" -> %>
                      <.configs config_rows={@config_rows} config_form={@config_form} config_feedback={@config_feedback} />
                    <% "dicts" -> %>
                      <.dicts dict_type_rows={@dict_type_rows} dict_data_rows={@dict_data_rows} dict_type_form={@dict_type_form} dict_data_form={@dict_data_form} selected_dict_type={@selected_dict_type} dict_feedback={@dict_feedback} />
                    <% "notices" -> %>
                      <.notices notice_rows={@notice_rows} notice_form={@notice_form} notice_feedback={@notice_feedback} />
                    <% "logs" -> %>
                      <.logs login_log_rows={@login_log_rows} operation_log_rows={@operation_log_rows} log_feedback={@log_feedback} />
                    <% "jobs" -> %>
                      <.jobs job_rows={@job_rows} job_form={@job_form} job_targets={@job_targets} job_feedback={@job_feedback} />
                    <% "job-logs" -> %>
                      <.job_logs job_log_rows={@job_log_rows} job_log_feedback={@job_log_feedback} />
                    <% "monitor" -> %>
                      <.monitor monitor_server_info={@monitor_server_info} monitor_cache_info={@monitor_cache_info} online_user_rows={@online_user_rows} network_status={@network_status} monitor_feedback={@monitor_feedback} />
                    <% "profile" -> %>
                      <.profile profile_form={@profile_form} password_form={@password_form} profile_feedback={@profile_feedback} avatar_upload={@uploads.avatar} />
                    <% _ -> %>
                      <div class="panel"><p>请选择一个管理模块。</p></div>
                  <% end %>
                <% else %>
                  <nav aria-label="个人模块">
                    <button type="button" class={if @active_panel == "profile", do: "active", else: ""} phx-click="show-panel" phx-value-panel="profile">个人资料</button>
                  </nav>
                  <%= if @active_panel == "profile" do %>
                    <.profile profile_form={@profile_form} password_form={@password_form} profile_feedback={@profile_feedback} avatar_upload={@uploads.avatar} />
                  <% else %>
                    <div class="card">
                      <h2>登录成功</h2>
                      <p class="muted">当前账号没有管理后台权限。</p>
                      <button type="button" class="secondary" phx-click="show-panel" phx-value-panel="profile">打开个人资料</button>
                    </div>
                  <% end %>
                <% end %>
              </div>
            <% else %>
              <div class="brand">
                <p>Keystone Phoenix</p>
                <h1>管理后台正在迁移到 LiveView</h1>
                <p>这个页面运行在 Phoenix LiveView 上，认证和业务数据由 Elixir、PostgreSQL 与 Redis 提供。</p>
              </div>
              <div class="card">
                <form id="login-form" phx-submit="login">
                  <h2>登录</h2>
                  <label for="username">用户名</label>
                  <input id="username" name="username" value={@username} autocomplete="username" required />
                  <label for="password">密码</label>
                  <input id="password" name="password" type="password" autocomplete="current-password" required />
                  <%= if @login_error do %><p class="error" role="alert"><%= @login_error %></p><% end %>
                  <button type="submit">登录</button>
                </form>
              </div>
            <% end %>
          </section>
        </main>
        <script src="/assets/phoenix/phoenix.min.js"></script>
        <script src="/assets/phoenix_live_view/phoenix_live_view.min.js"></script>
        <script>
          const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content");
          const liveSocket = new LiveView.LiveSocket("/live", Phoenix.Socket, {
            params: { _csrf_token: csrfToken }
          });
          liveSocket.connect();
          window.liveSocket = liveSocket;
        </script>
      </body>
    </html>
    """
  end
end
