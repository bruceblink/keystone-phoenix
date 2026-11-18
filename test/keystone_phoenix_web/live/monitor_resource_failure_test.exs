defmodule KeystonePhoenixWeb.MonitorResourceFailureTest do
  @moduledoc "监控资源失败、重试和旧数据保留的隔离验收。"

  use KeystonePhoenixWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias KeystonePhoenix.Repo
  alias KeystonePhoenix.Role.SysRole
  alias KeystonePhoenixWeb.LiveAuthenticationTestSupport, as: LiveSupport
  alias KeystonePhoenixWeb.Live.MonitorSupport

  @password "Strong!123"

  @tag :integration
  test "cache failure is isolated, retried alone, and marked stale after refresh", %{conn: conn} do
    role = Repo.get_by!(SysRole, role_key: "admin", deleted: false)
    {:ok, user} = LiveSupport.create_user(%{"role_id" => role.role_id})
    {:ok, view, _html} = live(conn, "/profile")

    render_submit(view, "login", %{"username" => user.username, "password" => @password})
    assert LiveSupport.live_socket(view).assigns.active_panel == "profile"

    Repo.query!("ALTER TABLE sys_login_info RENAME TO sys_login_info_unavailable")

    try do
      render_click(view, "show-panel", %{"panel" => "monitor"})

      initial = LiveSupport.live_socket(view).assigns
      assert initial.monitor_resource_states.server.status == :available
      assert initial.monitor_resource_states.network.status == :available
      assert initial.monitor_resource_states.cache.status == :stale
      assert initial.monitor_resource_states.online_users.status == :available
      assert initial.monitor_server_info != %{}
      assert initial.online_user_rows != []
      assert initial.monitor_cache_info["activeSessions"] >= 1

      assert has_element?(view, ".monitor-resource-error", "最新读取失败，保留旧数据")
      assert has_element?(view, ".monitor-resource-error button[phx-value-resource='cache']")
      assert has_element?(view, ".monitor-grid")
      assert has_element?(view, ".monitor-status-bar [role='status']", "PARTIAL")

      server_before_retry = initial.monitor_server_info
      online_before_retry = initial.online_user_rows

      Repo.query!("ALTER TABLE sys_login_info_unavailable RENAME TO sys_login_info")
      render_click(view, "retry-monitor", %{"resource" => "cache"})

      recovered = LiveSupport.live_socket(view).assigns
      assert recovered.monitor_resource_states.cache.status == :available
      assert recovered.monitor_cache_info["activeSessions"] >= 1
      assert recovered.monitor_server_info == server_before_retry
      assert recovered.online_user_rows == online_before_retry
      assert has_element?(view, ".monitor-status-bar [role='status']", "LIVE")

      Repo.query!("ALTER TABLE sys_login_info RENAME TO sys_login_info_unavailable")
      render_click(view, "refresh-monitor")

      stale = LiveSupport.live_socket(view).assigns
      assert stale.monitor_resource_states.cache.status == :stale
      assert stale.monitor_cache_info == recovered.monitor_cache_info
      assert stale.monitor_server_info != %{}
      assert stale.online_user_rows != []
      assert has_element?(view, ".monitor-resource-error", "最新读取失败，保留旧数据")
      assert has_element?(view, ".monitor-resource-error button[phx-value-resource='cache']")
      assert has_element?(view, ".monitor-status-bar [role='status']", "PARTIAL")
      assert stale.monitor_initial_error == nil
    after
      Repo.query!("ALTER TABLE sys_login_info_unavailable RENAME TO sys_login_info")
    end
  end

  test "monitor resource merge keeps old data only after a successful read", %{conn: _conn} do
    socket = %Phoenix.LiveView.Socket{
      assigns: %{
        __changed__: %{},
        monitor_cache_info: %{"activeSessions" => 4},
        monitor_server_info: %{"systemInfo" => %{"computerName" => "node-a"}},
        online_user_rows: [],
        online_user_total: 0,
        network_status: %{},
        monitor_resource_states: %{cache: %{status: :available, message: nil}}
      }
    }

    updated =
      MonitorSupport.apply_monitor_snapshot(socket, %{
        resource_states: %{cache: %{status: :unavailable, message: "缓存统计暂不可用，请重试。"}}
      })

    assert updated.assigns.monitor_cache_info["activeSessions"] == 4
    assert updated.assigns.monitor_resource_states.cache.status == :stale
    assert updated.assigns.monitor_server_info["systemInfo"]["computerName"] == "node-a"

    denied =
      MonitorSupport.apply_monitor_snapshot(socket, %{
        cache_info: %{},
        resource_states: %{cache: %{status: :forbidden, message: "没有读取权限。"}}
      })

    assert denied.assigns.monitor_cache_info == %{}
    assert denied.assigns.monitor_resource_states.cache.status == :forbidden
  end

  test "initial resource failure stays visible instead of appearing empty", %{conn: _conn} do
    socket = %Phoenix.LiveView.Socket{
      assigns: %{__changed__: %{}, network_status: %{}, monitor_resource_states: %{}}
    }

    updated =
      MonitorSupport.apply_monitor_snapshot(socket, %{
        cache_info: %{},
        resource_states: %{cache: %{status: :unavailable, message: "缓存统计暂不可用，请重试。"}}
      })

    assert updated.assigns.monitor_cache_info == %{}
    assert updated.assigns.monitor_resource_states.cache.status == :unavailable
    assert updated.assigns.monitor_overall_status == "OFFLINE"
    assert updated.assigns.network_status == %{}
  end
end
