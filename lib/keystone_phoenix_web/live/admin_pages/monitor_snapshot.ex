defmodule KeystonePhoenixWeb.Live.AdminPages.MonitorSnapshot do
  @moduledoc """
  按管理权限加载监控面板数据。

  模块只负责查询和聚合监控快照，不负责修改 LiveView socket。
  """

  alias KeystonePhoenix.Monitor
  alias KeystonePhoenixWeb.Live.AdminPages.Feedback

  # 各监控项独立检查权限，避免一个权限缺失时加载其他受保护数据。
  def load(admin?, permissions, page_num, page_size) do
    {server_info, server_error} = load_server(admin?, permissions)
    {cache_info, cache_error} = load_cache(admin?, permissions)

    {online_users, online_user_total, online_error} =
      load_online_users(admin?, permissions, page_num, page_size)

    %{
      server_info: server_info,
      cache_info: cache_info,
      online_users: online_users,
      online_user_total: online_user_total,
      network_status: load_network_status(admin?, permissions),
      feedback:
        [server_error, cache_error, online_error] |> Enum.find(&is_binary/1) |> error_feedback()
    }
  end

  defp load_server(admin?, permissions) do
    if admin? or "server:read" in permissions do
      case Monitor.server_info() do
        {:ok, info} -> {info, nil}
        {:error, :unavailable} -> {%{}, "主机监控数据暂不可用"}
      end
    else
      {%{}, nil}
    end
  end

  defp load_cache(admin?, permissions) do
    if admin? or "cache:refresh" in permissions do
      case Monitor.cache_info() do
        {:ok, info} -> {info, nil}
        _ -> {%{}, "ETS 缓存数据暂不可用"}
      end
    else
      {%{}, nil}
    end
  end

  defp load_online_users(admin?, permissions, page_num, page_size) do
    if admin? or "online-session:read" in permissions do
      case Monitor.online_users(%{"pageNum" => page_num, "pageSize" => page_size}) do
        {:ok, %{rows: rows, total: total}} -> {rows, total, nil}
        _ -> {[], 0, "在线会话数据暂不可用"}
      end
    else
      {[], 0, nil}
    end
  end

  defp load_network_status(admin?, permissions) do
    if admin? or "server:read" in permissions,
      do: Monitor.network_status(),
      else: %{}
  end

  defp error_feedback(nil), do: nil
  defp error_feedback(message), do: Feedback.error(message)
end
