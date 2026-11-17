defmodule KeystonePhoenixWeb.AdminListToolbarLayoutTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias KeystonePhoenixWeb.Live.AdminPages.{ApiKeys, Operations, System}

  # 核对操作组的位置和原有按钮交互属性，避免空列表或错误反馈时隐藏操作入口。
  test "system configuration and notices place ordered actions after their filters" do
    config_html =
      render_component(&System.configs/1, %{
        config_rows: [],
        config_feedback: {:error, "加载失败"},
        read_only: false
      })

    assert_in_order(config_html, [
      ~s(id="configs-filter"),
      ~s(aria-label="系统配置列表操作"),
      ~s(id="configs-table-title")
    ])

    assert_in_order(config_html, [~s(phx-click="new-config"), ~s(phx-click="refresh-config")])
    assert config_html =~ ~s(phx-click="new-config" phx-disable-with="处理中…")
    assert config_html =~ ~s(phx-click="refresh-config" phx-disable-with="刷新中…")

    read_only_config_html =
      render_component(&System.configs/1, %{
        config_rows: [],
        config_feedback: nil,
        read_only: true
      })

    refute read_only_config_html =~ ~s(phx-click="new-config")
    assert read_only_config_html =~ ~s(phx-click="refresh-config")

    notice_html =
      render_component(&System.notices/1, %{
        notice_rows: [],
        notice_feedback: nil,
        selected_notice_ids: [],
        read_only: false
      })

    assert_in_order(notice_html, [
      ~s(id="notice-filter"),
      ~s(aria-label="公告列表操作"),
      ~s(id="notices-table-title")
    ])

    assert_in_order(notice_html, [
      ~s(phx-click="new-notice"),
      ~s(phx-click="delete-notices"),
      ~s(phx-click="refresh-notices")
    ])

    assert notice_html =~ ~s(phx-confirm="确认删除选中的公告吗？")

    assert notice_html =~
             ~s(phx-click="delete-notices" phx-value-notice-ids="" phx-confirm="确认删除选中的公告吗？" disabled phx-disable-with="删除中…")
  end

  test "dictionary type and entry actions stay within their own list scopes" do
    unselected_html =
      render_component(&System.dicts/1, %{
        dict_type_rows: [],
        dict_data_rows: [],
        selected_dict_type: "",
        dict_feedback: nil,
        read_only: false
      })

    assert_in_order(unselected_html, [
      ~s(id="dict-type-filter"),
      ~s(aria-label="字典类型列表操作"),
      ~s(id="dict-types-title")
    ])

    assert unselected_html =~ ~s(id="dict-items-title")
    assert unselected_html =~ "选择类型后维护"
    refute unselected_html =~ ~s(aria-label="字典条目列表操作")

    selected_html =
      render_component(&System.dicts/1, %{
        dict_type_rows: [],
        dict_data_rows: [],
        selected_dict_type: "sys_user_sex",
        dict_feedback: {:error, "加载失败"},
        read_only: false
      })

    assert_in_order(selected_html, [
      ~s(id="dict-type-filter"),
      ~s(aria-label="字典类型列表操作"),
      ~s(id="dict-types-title"),
      ~s(id="dict-data-filter"),
      ~s(aria-label="字典条目列表操作"),
      ~s(id="dict-items-title")
    ])

    type_toolbar = toolbar_html(selected_html, "字典类型列表操作")
    item_toolbar = toolbar_html(selected_html, "字典条目列表操作")
    assert type_toolbar =~ ~s(phx-click="new-dict-type")
    assert type_toolbar =~ ~s(phx-click="refresh-dicts")
    refute type_toolbar =~ ~s(phx-click="new-dict-data")
    assert item_toolbar =~ ~s(phx-click="new-dict-data" phx-disable-with="处理中…")
    refute item_toolbar =~ ~s(phx-click="new-dict-type")

    read_only_html =
      render_component(&System.dicts/1, %{
        dict_type_rows: [],
        dict_data_rows: [],
        selected_dict_type: "sys_user_sex",
        dict_feedback: nil,
        read_only: true
      })

    refute read_only_html =~ ~s(phx-click="new-dict-type")
    refute read_only_html =~ ~s(phx-click="new-dict-data")
    assert read_only_html =~ ~s(phx-click="refresh-dicts")
  end

  test "API Key, job, and job log toolbars precede their respective list titles" do
    api_key_html =
      render_component(&ApiKeys.api_keys/1, %{
        api_key_rows: [],
        api_key_feedback: {:error, "加载失败"},
        active_modal: nil,
        permissions: ["api-key:create"],
        read_only: false
      })

    assert_in_order(api_key_html, [
      ~s(id="api-key-query"),
      ~s(aria-label="API Key 列表操作"),
      ~s(id="api-keys-table-title")
    ])

    assert_in_order(api_key_html, [~s(phx-click="new-api-key"), ~s(phx-click="refresh-api-keys")])
    assert api_key_html =~ ~s(phx-click="new-api-key" phx-disable-with="处理中…")
    assert api_key_html =~ ~s(phx-click="refresh-api-keys" phx-disable-with="刷新中…")

    no_create_permission =
      render_component(&ApiKeys.api_keys/1, %{
        api_key_rows: [],
        api_key_feedback: nil,
        active_modal: nil,
        permissions: [],
        read_only: false
      })

    refute no_create_permission =~ ~s(phx-click="new-api-key")
    assert no_create_permission =~ ~s(phx-click="refresh-api-keys")

    job_html =
      render_component(&Operations.jobs/1, %{
        job_rows: [],
        job_feedback: {:error, "加载失败"},
        selected_job_ids: [],
        active_modal: nil,
        read_only: false
      })

    assert_in_order(job_html, [
      ~s(id="jobs-filter"),
      ~s(aria-label="定时任务列表操作"),
      ~s(id="jobs-table-title")
    ])

    assert_in_order(job_html, [
      ~s(phx-click="new-job"),
      ~s(phx-click="delete-jobs"),
      ~s(phx-click="refresh-jobs")
    ])

    assert job_html =~ ~s(phx-confirm="确认删除选中的任务吗？")

    assert job_html =~
             ~s(phx-click="delete-jobs" phx-value-job-ids="" phx-confirm="确认删除选中的任务吗？" disabled phx-disable-with="删除中…")

    job_log_html =
      render_component(&Operations.job_logs/1, %{
        job_log_rows: [],
        job_log_feedback: {:error, "加载失败"}
      })

    assert_in_order(job_log_html, [
      ~s(aria-label="任务日志列表操作"),
      ~s(id="job-logs-title")
    ])

    assert job_log_html =~ ~s(phx-click="refresh-job-logs" phx-disable-with="刷新中…")
  end

  test "audit exports and refreshes remain scoped to each filter and list" do
    base = %{
      login_log_rows: [],
      operation_log_rows: [],
      log_feedback: {:error, "加载失败"},
      read_only: false
    }

    login_html = render_component(&System.logs/1, Map.put(base, :kind, "login"))

    assert_in_order(login_html, [
      ~s(id="login-log-filter"),
      ~s(aria-label="登录日志列表操作"),
      ~s(id="login-logs-title")
    ])

    assert_in_order(login_html, [
      ~s(phx-click="export-login-logs"),
      ~s(phx-click="refresh-login-logs")
    ])

    refute login_html =~ ~s(phx-click="export-operation-logs")
    refute login_html =~ ~s(phx-click="refresh-operation-logs")

    operation_html = render_component(&System.logs/1, Map.put(base, :kind, "operation"))

    assert_in_order(operation_html, [
      ~s(id="operation-log-filter"),
      ~s(aria-label="操作审计列表操作"),
      ~s(id="operation-logs-title")
    ])

    assert_in_order(operation_html, [
      ~s(phx-click="export-operation-logs"),
      ~s(phx-click="refresh-operation-logs")
    ])

    refute operation_html =~ ~s(phx-click="export-login-logs")
    refute operation_html =~ ~s(phx-click="refresh-login-logs")

    both_html = render_component(&System.logs/1, Map.put(base, :kind, "both"))
    assert both_html =~ ~s(phx-click="refresh-logs" phx-disable-with="刷新中…")
  end

  defp assert_in_order(html, markers) do
    positions =
      Enum.map(markers, fn marker ->
        case :binary.match(html, marker) do
          {position, _length} -> position
          :nomatch -> nil
        end
      end)

    assert Enum.all?(positions, &is_integer/1)
    assert positions == Enum.sort(positions)
  end

  defp toolbar_html(html, label) do
    [_prefix, toolbar] = String.split(html, ~s(aria-label="#{label}">), parts: 2)
    [content | _rest] = String.split(toolbar, "</div>", parts: 2)
    content
  end
end
