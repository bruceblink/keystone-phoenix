defmodule KeystonePhoenixWeb.Live.AdminPages.MonitorSnapshot do
  @moduledoc """
  按管理权限独立读取监控资源。

  每项读取结果包含数据和状态，单项失败不会丢弃其他资源的成功结果。
  """

  require Logger

  alias KeystonePhoenix.Monitor
  alias KeystonePhoenix.Security

  @resources [:server, :network, :cache, :online_users, :security]

  # 每项资源单独查询并合并结果，保留各自的失败和权限状态。
  def load(admin?, permissions, page_num, page_size, options \\ []) do
    Enum.reduce(@resources, %{resource_states: %{}}, fn resource, snapshot ->
      merge(snapshot, load_resource(resource, admin?, permissions, page_num, page_size, options))
    end)
  end

  # 单项重试只访问对应接口，避免无关资源失败覆盖页面状态。
  def load_resource(resource, admin?, permissions, page_num, page_size, options \\ []) do
    case resource do
      :server -> load_server(admin?, permissions, options)
      :network -> load_network(admin?, permissions, options)
      :cache -> load_cache(admin?, permissions, options)
      :online_users -> load_online_users(admin?, permissions, page_num, page_size, options)
      :security -> load_security(admin?, permissions, options)
      _ -> %{}
    end
  end

  defp load_server(admin?, permissions, options) do
    read_resource(
      :server,
      admin? or "server:read" in permissions,
      "主机信息",
      %{server_info: %{}},
      fn ->
        case monitor_call(options, &Monitor.server_info/0, &Monitor.server_info/1) do
          {:ok, info} -> %{server_info: info}
          {:error, reason} -> {:error, reason}
          _ -> {:error, :unavailable}
        end
      end
    )
  end

  defp load_network(admin?, permissions, options) do
    read_resource(
      :network,
      admin? or "server:read" in permissions,
      "网络状态",
      %{network_status: %{}},
      fn ->
        case monitor_call(options, &Monitor.network_status/0, &Monitor.network_status/1) do
          {:error, reason} -> {:error, reason}
          status when is_map(status) -> %{network_status: status}
          _ -> {:error, :unavailable}
        end
      end
    )
  end

  defp load_cache(admin?, permissions, options) do
    read_resource(
      :cache,
      admin? or "cache:refresh" in permissions,
      "缓存统计",
      %{cache_info: %{}},
      fn ->
        case monitor_call(options, &Monitor.cache_info/0, &Monitor.cache_info/1) do
          {:ok, info} -> %{cache_info: info}
          {:error, reason} -> {:error, reason}
          _ -> {:error, :unavailable}
        end
      end
    )
  end

  defp load_online_users(admin?, permissions, page_num, page_size, options) do
    read_resource(
      :online_users,
      admin? or "online-session:read" in permissions,
      "在线会话",
      %{online_users: [], online_user_total: 0},
      fn ->
        params = %{"pageNum" => page_num, "pageSize" => page_size}

        result =
          if options == [],
            do: Monitor.online_users(params),
            else: Monitor.online_users(params, options)

        case result do
          {:ok, %{rows: rows, total: total}} ->
            %{online_users: rows, online_user_total: total}

          {:error, reason} ->
            {:error, reason}

          _ ->
            {:error, :unavailable}
        end
      end
    )
  end

  defp load_security(admin?, permissions, options) do
    read_resource(
      :security,
      admin? or "audit:read" in permissions,
      "安全运营数据",
      %{
        security_metrics: %{},
        security_api_keys: %{},
        security_event_rows: [],
        security_event_total: 0
      },
      fn ->
        with {:ok, metrics} <- Security.metrics(options),
             {:ok, report} <- Security.report(%{"pageNum" => 1, "pageSize" => 20}, options) do
          events = get_in(report, ["securityEvents", "page"]) || []
          total = get_in(report, ["securityEvents", "total"]) || 0

          %{
            security_metrics: metrics,
            security_api_keys: report["apiKeys"] || %{},
            security_event_rows: events,
            security_event_total: total
          }
        else
          {:error, reason} -> {:error, reason}
        end
      end
    )
  end

  # 权限在查询入口检查；接口返回的权限或范围错误也保持为拒绝状态。
  defp read_resource(resource, allowed?, title, defaults, read) do
    result =
      if allowed? do
        try do
          read.()
        rescue
          error -> {:error, error}
        end
      else
        {:forbidden, :permission_denied}
      end

    case result do
      attrs when is_map(attrs) ->
        resource_result(resource, :available, nil, attrs)

      {:error, reason} when reason in [:permission_denied, :data_scope_denied] ->
        resource_result(resource, :forbidden, "当前账号没有读取#{title}的权限。", defaults)

      {:forbidden, _reason} ->
        resource_result(resource, :forbidden, "当前账号没有读取#{title}的权限。", defaults)

      {:error, reason} ->
        Logger.warning("monitor snapshot resource read failed",
          resource: resource,
          reason: safe_error_reason(reason)
        )

        resource_result(resource, :unavailable, "#{title}暂不可用，请重试。", defaults)

      _other ->
        Logger.warning("monitor snapshot resource returned an invalid result", resource: resource)
        resource_result(resource, :unavailable, "#{title}暂不可用，请重试。", defaults)
    end
  end

  defp resource_result(resource, status, message, attrs) do
    attrs
    |> Map.put(:resource_states, %{resource => %{status: status, message: message}})
  end

  defp monitor_call([], no_options, _with_options), do: no_options.()
  defp monitor_call(options, _no_options, with_options), do: with_options.(options)

  defp safe_error_reason(reason) when is_atom(reason), do: reason
  defp safe_error_reason(_reason), do: :unexpected

  defp merge(snapshot, resource_snapshot) do
    states = Map.merge(snapshot.resource_states, resource_snapshot.resource_states)

    snapshot
    |> Map.merge(Map.delete(resource_snapshot, :resource_states))
    |> Map.put(:resource_states, states)
  end
end
