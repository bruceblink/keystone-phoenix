defmodule KeystonePhoenixWeb.MonitorComponentTest do
  @moduledoc "监控面板组件测试，验证 admin-web 同构的趋势和指标结构。"

  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias KeystonePhoenixWeb.Live.AdminPages.Operations

  test "missing samples keep the neutral trend state" do
    html =
      render_component(&Operations.monitor/1, %{
        monitor_server_info: %{},
        monitor_cache_info: %{},
        online_user_rows: [],
        online_user_total: 0,
        network_status: %{"status" => "ONLINE", "checkedAt" => "2026-11-12T00:00:00Z"},
        monitor_feedback: nil
      })

    assert html =~ "trend-chart-empty"
    assert html =~ "暂无采样数据"
    refute html =~ "monitor-chart-bar"
  end

  test "sampled monitor data renders the admin-web trend structure" do
    html =
      render_component(&Operations.monitor/1, %{
        monitor_server_info: %{
          "cpuInfo" => %{"used" => 35.0, "cpuNum" => 8},
          "memoryInfo" => %{"usage" => 62.0},
          "jvmInfo" => %{"usage" => 18.0}
        },
        monitor_cache_info: %{},
        online_user_rows: [],
        online_user_total: 0,
        network_status: %{"status" => "ONLINE", "checkedAt" => "2026-11-12T00:00:00Z"},
        monitor_feedback: nil,
        monitor_trend: [
          %{timestamp: "2026-11-12T00:00:00Z", cpu: 35, memory: 62},
          %{timestamp: "2026-11-12T00:15:00Z", cpu: 42, memory: 65}
        ]
      })

    assert html =~ ~s(class="trend-chart-line trend-chart-line-cyan")
    assert html =~ ~s(class="trend-chart-line trend-chart-line-indigo")
    assert html =~ "CPU 和内存 30 分钟趋势图"
    assert html =~ "网络入口"
    assert html =~ "BEAM 内存使用率"
    assert html =~ "Reductions"
    assert html =~ "—"
    refute html =~ "monitor-chart-bar"
  end

  test "initial monitor loading state is explicit" do
    html =
      render_component(&Operations.monitor/1, %{
        monitor_server_info: %{},
        monitor_cache_info: %{},
        online_user_rows: [],
        online_user_total: 0,
        network_status: %{},
        monitor_feedback: nil,
        monitor_loading: true,
        monitor_initial_error: nil
      })

    assert html =~ ~s(id="monitor-loading")
    assert html =~ "正在读取监控快照"
    refute html =~ ~s(class="monitor-grid")
  end

  test "initial monitor failure exposes a retry action" do
    html =
      render_component(&Operations.monitor/1, %{
        monitor_server_info: %{},
        monitor_cache_info: %{},
        online_user_rows: [],
        online_user_total: 0,
        network_status: %{},
        monitor_feedback: nil,
        monitor_loading: false,
        monitor_initial_error: {:error, "service_unavailable", "监控快照暂不可用，请重试"}
      })

    assert html =~ ~s(id="monitor-initial-error")
    assert html =~ ~s(role="alert")
    assert html =~ "监控快照暂不可用，请重试"
    assert html =~ ~s(phx-click="retry-monitor")
    refute html =~ ~s(class="monitor-grid")
  end

  test "resource failures do not hide other data or render a false empty state" do
    html =
      render_component(&Operations.monitor/1, %{
        monitor_server_info: %{},
        monitor_cache_info: %{},
        online_user_rows: [],
        online_user_total: 0,
        network_status: %{"status" => "DEGRADED"},
        monitor_overall_status: "DEGRADED",
        monitor_feedback: nil,
        monitor_resource_states: %{
          server: %{status: :unavailable, message: "主机信息暂不可用，请重试。"},
          network: %{status: :available},
          cache: %{status: :unavailable, message: "缓存统计暂不可用，请重试。"},
          online_users: %{status: :unavailable, message: "在线会话暂不可用，请重试。"}
        }
      })

    assert html =~ ~s(class="monitor-grid")
    assert html =~ "PARTIAL"
    assert html =~ "无法读取缓存统计"
    assert html =~ "无法读取主机信息"
    assert html =~ "在线会话数据暂不可用"
    assert html =~ ~s(phx-value-resource="cache")
    assert html =~ ~s(phx-value-resource="server")
    assert html =~ ~s(phx-value-resource="online_users")
    refute html =~ "暂无采样数据"
    refute html =~ "暂无在线会话"
    refute html =~ "0 个活跃会话"
  end

  test "permission state is explicit and does not offer a data retry" do
    html =
      render_component(&Operations.monitor/1, %{
        monitor_server_info: %{},
        monitor_cache_info: %{},
        online_user_rows: [],
        online_user_total: 0,
        network_status: %{},
        monitor_feedback: nil,
        monitor_resource_states: %{online_users: %{status: :forbidden}}
      })

    assert html =~ "当前账号没有读取在线会话的权限。"
    refute html =~ ~s(phx-value-resource="online_users")
    refute html =~ "暂无在线会话"
  end
end
