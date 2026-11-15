defmodule KeystonePhoenixWeb.AdminNoticeEmptyTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias KeystonePhoenixWeb.Live.AdminPages.System

  test "notice panel hides the table when no notices match" do
    html =
      render_component(&System.notices/1, %{
        notice_rows: [],
        notice_form: %{"noticeId" => ""},
        notice_feedback: nil,
        notice_filter: %{"title" => "", "published" => "all"}
      })

    assert html =~ "没有匹配的公告"
    refute html =~ "notices-table-wrap"
  end
end
