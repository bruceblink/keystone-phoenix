defmodule KeystonePhoenixWeb.AdminNoticeFilterTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias KeystonePhoenixWeb.Live.AdminPages.System

  test "applies notice filters after submit instead of every field change" do
    # 公告筛选必须等待用户提交，保持与 admin-web 的两阶段筛选行为一致。
    html =
      render_component(&System.notices/1, %{
        notice_rows: [],
        notice_form: %{"noticeId" => ""},
        notice_feedback: nil,
        notice_filter: %{"title" => "", "published" => "all"},
        read_only: false
      })

    assert html =~ ~s(phx-submit="filter-notices")
    refute html =~ ~s(phx-change="filter-notices")
  end
end
