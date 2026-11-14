defmodule KeystonePhoenixWeb.Live.AdminPages.MonitorSnapshot do
  @moduledoc """
  按管理权限加载监控面板数据。

  模块只负责查询和聚合监控快照，不负责修改 LiveView socket。
  """

  alias KeystonePhoenix.Monitor
  alias KeystonePhoenix.Security
  alias KeystonePhoenixWeb.Live.AdminPages.Feedback

  # 各监控项独立检查权限，避免一个权限缺失时加载其他受保护数据。
  def load(admin?, permissions, page_num, page_size, options \\ []) do
    {server_info, server_error} = load_server(admin?, permissions, options)
    {cache_info, cache_error} = load_cache(admin?, permissions, options)

    {online_users, online_user_total, online_error} =
      load_online_users(admin?, permissions, page_num, page_size, options)

    {security_metrics, security_api_keys, security_events, security_event_total, security_error} =
      load_security(admin?, permissions, options)

    %{
      server_info: server_info,
      cache_info: cache_info,
      online_users: online_users,
      online_user_total: online_user_total,
      network_status: load_network_status(admin?, permissions, options),
      security_access: admin? or "audit:read" in permissions,
      security_metrics: security_metrics,
      security_api_keys: security_api_keys,
      security_event_rows: security_events,
      security_event_total: security_event_total,
      feedback:
        [server_error, cache_error, online_error, security_error]
        |> Enum.find(&is_binary/1)
        |> error_feedback()
    }
  end

  defp load_server(admin?, permissions, options) do
    if admin? or "server:read" in permissions do
      result = if options == [], do: Monitor.server_info(), else: Monitor.server_info(options)

      case result do
        {:ok, info} -> {info, nil}
        {:error, :unavailable} -> {%{}, "主机监控数据暂不可用"}
      end
    else
      {%{}, nil}
    end
  end

  defp load_cache(admin?, permissions, options) do
    if admin? or "cache:refresh" in permissions do
      result = if options == [], do: Monitor.cache_info(), else: Monitor.cache_info(options)

      case result do
        {:ok, info} -> {info, nil}
        _ -> {%{}, "ETS 缓存数据暂不可用"}
      end
    else
      {%{}, nil}
    end
  end

  defp load_online_users(admin?, permissions, page_num, page_size, options) do
    if admin? or "online-session:read" in permissions do
      params = %{"pageNum" => page_num, "pageSize" => page_size}

      result =
        if options == [],
          do: Monitor.online_users(params),
          else: Monitor.online_users(params, options)

      case result do
        {:ok, %{rows: rows, total: total}} -> {rows, total, nil}
        _ -> {[], 0, "在线会话数据暂不可用"}
      end
    else
      {[], 0, nil}
    end
  end

  defp load_network_status(admin?, permissions, options) do
    if admin? or "server:read" in permissions,
      do: if(options == [], do: Monitor.network_status(), else: Monitor.network_status(options)),
      else: %{}
  end

  defp load_security(admin?, permissions, options) do
    if admin? or "audit:read" in permissions do
      with {:ok, metrics} <- Security.metrics(options),
           {:ok, report} <- Security.report(%{"pageNum" => 1, "pageSize" => 20}, options) do
        events = get_in(report, ["securityEvents", "page"]) || []
        total = get_in(report, ["securityEvents", "total"]) || 0
        {metrics, report["apiKeys"] || %{}, events, total, nil}
      else
        {:error, _reason} -> {%{}, %{}, [], 0, "安全运营数据暂不可用"}
      end
    else
      {%{}, %{}, [], 0, nil}
    end
  end

  defp error_feedback(nil), do: nil
  defp error_feedback(message), do: Feedback.error(message)
end
