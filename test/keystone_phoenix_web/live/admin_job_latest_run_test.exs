defmodule KeystonePhoenixWeb.AdminJobLatestRunTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias KeystonePhoenixWeb.Live.AdminPages.Operations

  test "shows the latest execution result and completion time in the task row" do
    html =
      render_component(&Operations.jobs/1, %{
        job_rows: [
          %{
            "jobId" => "00000000-0000-7000-8000-000000000001",
            "jobCode" => "heartbeat",
            "jobName" => "系统心跳",
            "jobGroup" => "SYSTEM",
            "cronExpression" => "*/30 * * * * *",
            "status" => 1,
            "lastStatus" => "SUCCESS",
            "lastRunAt" => "2026-11-18T10:20:30.123456Z"
          }
        ],
        job_feedback: nil,
        job_form: %{"jobId" => ""},
        job_targets: [],
        selected_job_ids: []
      })

    assert html =~ "最近成功"
    assert html =~ ~s(phx-hook="LocalDateTime")
    assert html =~ ~s(data-utc-time="2026-11-18T10:20:30.123456Z")
    assert html =~ "2026-11-18T10:20:30.123456Z"
  end
end
