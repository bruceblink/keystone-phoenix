defmodule KeystonePhoenixWeb.Live.MonitorSupport do
  @moduledoc "负责读取监控快照，并保持首屏读取失败的可见状态。"

  import Phoenix.Component, only: [assign: 2]

  alias KeystonePhoenixWeb.Live.AdminPages.Feedback
  alias KeystonePhoenixWeb.Live.AdminPages.MonitorSnapshot
  alias KeystonePhoenixWeb.Live.AdminSupport

  @monitor_permissions ["cache:refresh", "server:read", "online-session:read", "audit:read"]

  # 监控查询失败时保留旧快照；首次失败进入可重试状态，避免把故障显示成空数据。
  def assign_monitor(socket, feedback \\ nil) do
    monitor =
      MonitorSnapshot.load(
        AdminSupport.admin_socket?(socket),
        List.wrap(socket.assigns[:permissions]),
        get_in(socket.assigns, [:page_nums, "online-users"]) || 1,
        get_in(socket.assigns, [:page_sizes, "online-users"]) || 50,
        AdminSupport.authorization_options(socket)
      )

    cond do
      monitor.error_reason && socket.assigns[:monitor_loaded] ->
        assign(socket,
          active_panel: "monitor",
          monitor_loading: false,
          monitor_initial_error: nil,
          monitor_feedback: feedback || monitor.feedback
        )

      monitor.error_reason ->
        assign(socket,
          active_panel: "monitor",
          monitor_loading: false,
          monitor_initial_error:
            monitor.feedback || Feedback.error(:service_unavailable, "监控快照暂不可用，请重试"),
          monitor_feedback: nil,
          monitor_loaded: false
        )

      true ->
        assign(socket,
          active_panel: "monitor",
          monitor_server_info: monitor.server_info,
          monitor_cache_info: monitor.cache_info,
          online_user_rows: monitor.online_users,
          online_user_total: monitor.online_user_total,
          network_status: monitor.network_status,
          security_access: monitor.security_access,
          security_metrics: monitor.security_metrics,
          security_api_keys: monitor.security_api_keys,
          security_event_rows: monitor.security_event_rows,
          security_event_total: monitor.security_event_total,
          monitor_loading: false,
          monitor_initial_error: nil,
          monitor_loaded: true,
          monitor_feedback: feedback || monitor.feedback
        )
    end
  end

  def access?(socket) do
    AdminSupport.admin_socket?(socket) or
      Enum.any?(@monitor_permissions, &AdminSupport.permission_socket?(socket, &1))
  end
end
