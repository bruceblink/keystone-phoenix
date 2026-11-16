defmodule KeystonePhoenixWeb.AdminPageIconsTest do
  @moduledoc "页面图标测试，确认表格和空状态使用统一 SVG 图标。"

  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias KeystonePhoenixWeb.Live.AdminPages.{Operations, Organization, System}

  test "jobs table and empty states use SVG icons" do
    empty_html =
      render_component(&Operations.jobs/1, %{
        job_rows: [],
        job_form: %{},
        job_targets: [],
        job_feedback: nil,
        read_only: true
      })

    assert empty_html =~ ~s(class="jobs-empty-icon")
    assert empty_html =~ "nav-icon-svg"

    rows_html =
      render_component(&Operations.jobs/1, %{
        job_rows: [%{"jobId" => "job-1", "jobName" => "健康检查", "jobCode" => "health-check"}],
        job_form: %{},
        job_targets: [],
        job_feedback: nil,
        read_only: true
      })

    assert rows_html =~ ~s(class="job-marker")
    assert rows_html =~ "nav-icon-svg"
    refute rows_html =~ "▣"

    logs_html =
      render_component(&Operations.job_logs/1, %{
        job_log_rows: [],
        job_log_feedback: nil,
        read_only: true
      })

    assert logs_html =~ ~s(class="jobs-empty-icon")
    assert logs_html =~ "nav-icon-svg"
  end

  test "post table and empty state use SVG icons" do
    empty_html =
      render_component(&Organization.posts/1, %{
        post_rows: [],
        post_form: %{},
        post_feedback: nil,
        read_only: true
      })

    assert empty_html =~ ~s(class="posts-empty-icon")
    assert empty_html =~ "nav-icon-svg"

    rows_html =
      render_component(&Organization.posts/1, %{
        post_rows: [%{"postId" => "post-1", "postName" => "运维", "postCode" => "ops"}],
        post_form: %{},
        post_feedback: nil,
        read_only: true
      })

    assert rows_html =~ ~s(class="post-cell-icon")
    assert rows_html =~ "nav-icon-svg"
    refute rows_html =~ "▣"
  end

  test "notice table and empty state use SVG icons" do
    empty_html =
      render_component(&System.notices/1, %{
        notice_rows: [],
        notice_form: %{},
        notice_feedback: nil,
        read_only: true
      })

    assert empty_html =~ ~s(class="notices-empty-icon")
    assert empty_html =~ "nav-icon-svg"

    rows_html =
      render_component(&System.notices/1, %{
        notice_rows: [
          %{
            "noticeId" => "notice-1",
            "noticeTitle" => "维护通知",
            "noticeContent" => "系统维护窗口",
            "noticeType" => 1,
            "published" => true
          }
        ],
        notice_form: %{},
        notice_feedback: nil,
        read_only: true
      })

    assert rows_html =~ ~s(class="notice-cell-icon")
    assert rows_html =~ "nav-icon-svg"
    refute rows_html =~ "▣"
  end
end
