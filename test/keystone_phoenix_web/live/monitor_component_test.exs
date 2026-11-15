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
end
