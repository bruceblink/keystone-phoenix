defmodule KeystonePhoenixWeb.Live.MonitorSupport do
  @moduledoc "按资源更新监控数据，并保留可重试的失败状态。"

  import Phoenix.Component, only: [assign: 2, assign: 3]

  alias KeystonePhoenixWeb.Live.AdminPages.MonitorSnapshot
  alias KeystonePhoenixWeb.Live.AdminSupport

  @monitor_permissions ["cache:refresh", "server:read", "online-session:read", "audit:read"]
  @visible_resources [:server, :network, :cache, :online_users]
  @resource_fields %{
    server: [server_info: :monitor_server_info],
    network: [network_status: :network_status],
    cache: [cache_info: :monitor_cache_info],
    online_users: [online_users: :online_user_rows, online_user_total: :online_user_total],
    security: [
      security_metrics: :security_metrics,
      security_api_keys: :security_api_keys,
      security_event_rows: :security_event_rows,
      security_event_total: :security_event_total
    ]
  }
  @resource_defaults %{
    server: [monitor_server_info: %{}],
    network: [network_status: %{}],
    cache: [monitor_cache_info: %{}],
    online_users: [online_user_rows: [], online_user_total: 0],
    security: [
      security_metrics: %{},
      security_api_keys: %{},
      security_event_rows: [],
      security_event_total: 0
    ]
  }

  # 完整刷新逐项合并结果；一项失败不影响其他已成功读取的数据。
  def assign_monitor(socket, feedback \\ nil) do
    snapshot =
      MonitorSnapshot.load(
        AdminSupport.admin_socket?(socket),
        List.wrap(socket.assigns[:permissions]),
        get_in(socket.assigns, [:page_nums, "online-users"]) || 1,
        get_in(socket.assigns, [:page_sizes, "online-users"]) || 50,
        AdminSupport.authorization_options(socket)
      )

    apply_monitor_snapshot(socket, snapshot, feedback)
  end

  # 单项重试只更新对应资源，保留其他数据、权限和失败状态。
  def assign_monitor_resource(socket, resource, feedback \\ nil) do
    snapshot =
      MonitorSnapshot.load_resource(
        resource,
        AdminSupport.admin_socket?(socket),
        List.wrap(socket.assigns[:permissions]),
        get_in(socket.assigns, [:page_nums, "online-users"]) || 1,
        get_in(socket.assigns, [:page_sizes, "online-users"]) || 50,
        AdminSupport.authorization_options(socket)
      )

    apply_monitor_snapshot(socket, snapshot, feedback)
  end

  # 按资源状态更新字段；失败时保留旧值，权限被拒绝时清空旧值。
  def apply_monitor_snapshot(socket, snapshot, feedback \\ nil) do
    socket =
      Enum.reduce(Map.keys(snapshot.resource_states), socket, fn resource, current ->
        apply_resource_result(current, resource, snapshot)
      end)

    socket
    |> assign(
      active_panel: "monitor",
      monitor_loading: false,
      monitor_initial_error: nil,
      monitor_loaded: true,
      monitor_feedback: feedback
    )
    |> assign_aggregate_status()
  end

  # 新数据替换旧值；初次失败显示错误，后续失败保留旧值并标记为过期。
  def apply_resource_result(socket, resource, snapshot) do
    state = get_in(snapshot, [:resource_states, resource])
    previous = get_in(socket.assigns, [:monitor_resource_states, resource])

    case state do
      %{status: :available} ->
        socket
        |> assign_resource_fields(resource, snapshot)
        |> put_resource_state(resource, state)
        |> assign_security_access(resource, true)

      %{status: :forbidden} ->
        socket
        |> assign_defaults(resource)
        |> put_resource_state(resource, state)
        |> assign_security_access(resource, false)

      %{status: :unavailable} ->
        if previous && previous.status in [:available, :stale] do
          stale_state = %{
            state
            | status: :stale,
              message: "#{state.message}当前仍显示上一次成功数据。"
          }

          socket
          |> put_resource_state(resource, stale_state)
          |> assign_security_access(resource, true)
        else
          socket
          |> assign_defaults(resource)
          |> put_resource_state(resource, state)
          |> assign_security_access(resource, true)
        end

      _other ->
        socket
    end
  end

  def access?(socket) do
    AdminSupport.admin_socket?(socket) or
      Enum.any?(@monitor_permissions, &AdminSupport.permission_socket?(socket, &1))
  end

  defp assign_resource_fields(socket, resource, snapshot) do
    Enum.reduce(Map.fetch!(@resource_fields, resource), socket, fn {source, target}, current ->
      assign(current, target, Map.fetch!(snapshot, source))
    end)
  end

  defp assign_defaults(socket, resource) do
    Enum.reduce(Map.fetch!(@resource_defaults, resource), socket, fn {target, value}, current ->
      assign(current, target, value)
    end)
  end

  defp put_resource_state(socket, resource, state) do
    states = Map.put(socket.assigns[:monitor_resource_states] || %{}, resource, state)
    assign(socket, monitor_resource_states: states)
  end

  defp assign_security_access(socket, :security, accessible?),
    do: assign(socket, security_access: accessible?)

  defp assign_security_access(socket, _resource, _accessible?), do: socket

  defp assign_aggregate_status(socket) do
    states = socket.assigns.monitor_resource_states

    allowed_states =
      @visible_resources
      |> Enum.map(&Map.get(states, &1))
      |> Enum.reject(&is_nil/1)
      |> Enum.reject(&(&1.status == :forbidden))
      |> Enum.map(& &1.status)

    network_state = Map.get(states, :network)
    status = aggregate_status(allowed_states, network_state)
    assign(socket, monitor_overall_status: status)
  end

  defp aggregate_status([], _network), do: "PARTIAL"

  defp aggregate_status(statuses, network) when statuses != [] do
    cond do
      Enum.all?(statuses, &(&1 == :unavailable)) -> "OFFLINE"
      Enum.all?(statuses, &(&1 in [:unavailable, :stale])) -> "STALE"
      Enum.any?(statuses, &(&1 in [:unavailable, :stale])) -> "DEGRADED"
      network && network.status == :available -> "ONLINE"
      true -> "PARTIAL"
    end
  end
end
