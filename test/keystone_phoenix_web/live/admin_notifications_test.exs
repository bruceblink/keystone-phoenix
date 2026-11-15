defmodule KeystonePhoenixWeb.AdminNotificationsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias KeystonePhoenixWeb.Live.AdminPages.Notifications

  test "renders notification list and opens a selected detail" do
    notifications = [
      %{
        "id" => "notification-1",
        "title" => "维护通知",
        "content" => "今晚进行系统维护。",
        "noticeType" => "notification",
        "publishAt" => "2026-11-15T02:00:00Z",
        "createdAt" => "2026-11-15T01:00:00Z"
      }
    ]

    list_html =
      render_component(&Notifications.menu/1, %{
        open: true,
        notifications: notifications,
        selected: nil
      })

    assert list_html =~ "站内通知"
    assert list_html =~ "维护通知"
    assert list_html =~ ~s(phx-click="open-notification")
    refute list_html =~ "通知详情"

    detail_html =
      render_component(&Notifications.menu/1, %{
        open: true,
        notifications: notifications,
        selected: hd(notifications)
      })

    assert detail_html =~ "通知详情"
    assert detail_html =~ "今晚进行系统维护。"
    assert detail_html =~ ~s(phx-click="back-notifications")
  end
end
