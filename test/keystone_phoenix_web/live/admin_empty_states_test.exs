defmodule KeystonePhoenixWeb.AdminEmptyStatesTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias KeystonePhoenixWeb.Live.AdminPages.{Operations, System}

  test "dictionary data empty state does not render an empty table" do
    html =
      render_component(&System.dicts/1, %{
        dict_type_rows: [],
        dict_data_rows: [],
        dict_type_form: %{},
        dict_data_form: %{},
        selected_dict_type: "system_status",
        dict_feedback: nil
      })

    assert html =~ "暂无字典条目"
    refute html =~ "dictionary-items-table"
    refute html =~ "<table"
  end

  test "audit log empty states do not render empty tables" do
    html =
      render_component(&System.logs/1, %{
        login_log_rows: [],
        operation_log_rows: [],
        log_feedback: nil,
        kind: "both"
      })

    assert html =~ "暂无登录日志数据"
    assert html =~ "暂无操作日志数据"
    refute html =~ ~s(<table class="audit-table")
    refute html =~ "<table"
  end

  test "job log empty state does not render an empty table" do
    html =
      render_component(&Operations.job_logs/1, %{
        job_log_rows: [],
        job_log_feedback: nil
      })

    assert html =~ "暂无任务日志"
    refute html =~ ~s(<table class="jobs-table")
    refute html =~ "<table"
  end
end
