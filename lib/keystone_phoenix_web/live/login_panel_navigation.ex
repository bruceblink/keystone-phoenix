defmodule KeystonePhoenixWeb.Live.LoginPanelNavigation do
  @moduledoc "按当前会话权限选择面板并恢复安全的页面深链接。"

  import Phoenix.Component, only: [assign: 2]

  alias KeystonePhoenixWeb.Live.AdminEvents.AccountsDeepLinks
  alias KeystonePhoenixWeb.Live.AdminEvents.AuditDeepLinks
  alias KeystonePhoenixWeb.Live.AdminEvents.OrganizationDeepLinks
  alias KeystonePhoenixWeb.Live.AdminEvents.OperationsDeepLinks
  alias KeystonePhoenixWeb.Live.AdminEvents.Operations, as: OperationsEvents
  alias KeystonePhoenixWeb.Live.AdminEvents.Security, as: SecurityEvents
  alias KeystonePhoenixWeb.Live.AdminPages.FilterNavigation
  alias KeystonePhoenixWeb.Live.AdminPages.Navigation
  alias KeystonePhoenixWeb.Live.AdminPages.Pagination
  alias KeystonePhoenixWeb.Live.AdminSupport

  # 已登录的 URL 只能选择当前会话可访问的面板；拒绝时清除原查询条件。
  def handle_params(params, uri, socket) do
    requested_panel = Navigation.panel_for_path(uri)
    panel = Navigation.authorized_panel(socket.assigns.panel_access, requested_panel)
    socket = assign(socket, current_uri: uri)

    if panel == requested_panel do
      if socket.assigns.active_panel == panel and route_state_matches?(socket, panel, params),
        do: {:noreply, socket},
        else: activate_panel(socket, panel, params)
    else
      activate_and_redirect(socket, panel, uri)
    end
  end

  # 登录成功后保留获准的原面板；默认首页和无权地址改到第一个可访问面板。
  def restore_after_login(socket, uri) do
    params = URI.parse(uri).query |> then(&URI.decode_query(&1 || ""))
    requested_panel = Navigation.panel_for_path(uri)
    panel = Navigation.authorized_panel(socket.assigns.panel_access, requested_panel)

    if panel == requested_panel do
      socket
      |> assign(current_uri: uri)
      |> activate_panel(panel, params)
    else
      activate_and_redirect(socket, panel, uri)
    end
  end

  # 常规面板操作已完成读取；匹配 URL 状态时只同步地址，避免重读覆盖反馈。
  defp route_state_matches?(socket, panel, params) do
    route_assigns = FilterNavigation.assigns(panel, params)

    candidate =
      socket
      |> assign(route_assigns)
      |> FilterNavigation.apply_page(panel, params)

    Enum.all?(route_assigns, fn {key, value} -> socket.assigns[key] == value end) and
      candidate.assigns.page_nums == socket.assigns.page_nums and
      route_page_valid?(socket, panel)
  end

  # 分页事件也需保护越界页；越界地址仍由完整恢复路径校正到有效页。
  defp route_page_valid?(socket, "users"),
    do: page_valid?(socket, "users", :user_total)

  defp route_page_valid?(socket, "login-logs"),
    do: page_valid?(socket, "login-logs", :login_log_total)

  defp route_page_valid?(socket, "operation-logs"),
    do: page_valid?(socket, "operation-logs", :operation_log_total)

  defp route_page_valid?(_socket, _panel), do: true

  defp page_valid?(socket, panel, total_key) do
    page = get_in(socket.assigns, [:page_nums, panel]) || 1
    size = get_in(socket.assigns, [:page_sizes, panel]) || 20
    page <= Pagination.page_count(Map.get(socket.assigns, total_key, 0), size)
  end

  # 拒绝深链接时先读取默认授权页面，再清理 URL，确保资料页等回退页面完整显示。
  defp activate_and_redirect(socket, panel, uri) do
    {:noreply, socket} =
      socket
      |> assign(current_uri: uri)
      |> activate_panel(panel, %{})

    {:noreply, Phoenix.LiveView.push_patch(socket, to: Navigation.panel_path(panel))}
  end

  # 已授权的深链接加载必要状态；其他页面使用登录时按权限读取的数据。
  defp activate_panel(socket, panel, params) do
    socket =
      socket
      |> assign(active_panel: panel)
      |> assign(FilterNavigation.assigns(panel, params))
      |> FilterNavigation.apply_page(panel, params)

    restore_panel(socket, panel)
  end

  defp restore_panel(socket, "jobs"),
    do: OperationsDeepLinks.restore_jobs_from_deep_link(socket)

  defp restore_panel(socket, "users"),
    do: AccountsDeepLinks.restore_users_from_deep_link(socket)

  defp restore_panel(socket, "menus"),
    do: OrganizationDeepLinks.restore_menus_from_deep_link(socket)

  defp restore_panel(socket, "depts"),
    do: OrganizationDeepLinks.restore_departments_from_deep_link(socket)

  defp restore_panel(socket, "login-logs"),
    do: AuditDeepLinks.restore_login_logs_from_deep_link(socket)

  defp restore_panel(socket, "operation-logs"),
    do: AuditDeepLinks.restore_operation_logs_from_deep_link(socket)

  defp restore_panel(socket, "api-keys") do
    SecurityEvents.handle_event(
      "refresh-api-keys",
      %{},
      assign(socket, issued_api_key: nil)
    )
  end

  defp restore_panel(socket, "profile"),
    do: {:noreply, AdminSupport.assign_profile(socket)}

  defp restore_panel(socket, panel) do
    OperationsEvents.restore_selected_job_if_needed(socket, panel)
  end
end
