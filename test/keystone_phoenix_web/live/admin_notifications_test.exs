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
        error: nil,
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
        error: nil,
        selected: hd(notifications)
      })

    assert detail_html =~ "通知详情"
    assert detail_html =~ "今晚进行系统维护。"
    assert detail_html =~ ~s(phx-click="back-notifications")
  end

  test "renders a retry action when public notifications fail" do
    html =
      render_component(&Notifications.menu/1, %{
        open: true,
        notifications: [],
        error: "站内通知暂时无法读取，请重试",
        selected: nil
      })

    assert html =~ ~s(role="alert")
    assert html =~ "站内通知暂时无法读取，请重试"
    assert html =~ ~s(phx-click="retry-notifications")
    refute html =~ "暂无站内通知"
  end

  test "formats ISO notification timestamps like admin-web" do
    assert Notifications.notification_time("2026-11-15T02:00:00Z") == "2026-11-15 02:00:00"
  end
end
