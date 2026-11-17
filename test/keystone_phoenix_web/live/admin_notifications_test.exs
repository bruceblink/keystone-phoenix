defmodule KeystonePhoenixWeb.AdminNotificationsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias KeystonePhoenixWeb.Live.AdminPages.Notifications

  test "renders notification list and opens a selected detail" do
    notifications = [
      %{
        "id" => "notification-1",
        "type" => "api_key.created",
        "title" => "维护通知",
        "content" => "今晚进行系统维护。",
        "createdAt" => "2026-11-15T01:00:00Z",
        "readAt" => nil
      }
    ]

    list_html =
      render_component(&Notifications.menu/1, %{
        open: true,
        loading: false,
        notifications: notifications,
        unread_count: 1,
        error: nil,
        read_error: nil,
        selected: nil
      })

    assert list_html =~ "站内通知"
    assert list_html =~ "维护通知"
    assert list_html =~ ~s(phx-click="open-notification")
    assert list_html =~ ~s(phx-hook="LocalDateTime")
    assert list_html =~ ~s(data-utc-time="2026-11-15T01:00:00Z")
    assert list_html =~ ~s(class="notification-count")
    assert list_html =~ ~s(aria-label="通知，1 条未读")
    refute list_html =~ "通知详情"

    detail_html =
      render_component(&Notifications.menu/1, %{
        open: true,
        loading: false,
        notifications: notifications,
        unread_count: 1,
        error: nil,
        read_error: nil,
        selected: hd(notifications)
      })

    assert detail_html =~ "通知详情"
    assert detail_html =~ "今晚进行系统维护。"
    assert detail_html =~ ~s(phx-click="back-notifications")
  end

  test "keeps notification details visible when marking it read fails" do
    notification = %{
      "id" => "notification-2",
      "type" => "api_key.created",
      "title" => "API Key 已签发",
      "content" => "一个 API Key 已成功签发。",
      "createdAt" => "2026-11-15T01:00:00Z",
      "readAt" => nil
    }

    html =
      render_component(&Notifications.menu/1, %{
        open: true,
        loading: false,
        notifications: [notification],
        unread_count: 1,
        error: nil,
        read_error: "站内通知暂时无法读取，请重试",
        read_error_action: "retry-notification-read",
        read_error_label: "重试标记已读",
        selected: notification
      })

    assert html =~ notification["title"]
    assert html =~ notification["content"]
    assert html =~ ~s(role="alert")
    assert html =~ "站内通知暂时无法读取，请重试"
    assert html =~ ~s(phx-click="retry-notification-read")
    assert html =~ "重试标记已读"
    refute html =~ "暂无站内通知"
  end

  test "offers a list refresh when the selected notification no longer exists" do
    notification = %{
      "id" => "notification-3",
      "type" => "api_key.created",
      "title" => "API Key 已签发",
      "content" => "一个 API Key 已成功签发。",
      "createdAt" => "2026-11-15T01:00:00Z",
      "readAt" => nil
    }

    html =
      render_component(&Notifications.menu/1, %{
        open: true,
        loading: false,
        notifications: [notification],
        unread_count: 1,
        error: nil,
        read_error: "通知不存在或已移除，请刷新后重试",
        read_error_action: "retry-notifications",
        read_error_label: "刷新通知列表",
        selected: notification
      })

    assert html =~ notification["content"]
    assert html =~ ~s(phx-click="retry-notifications")
    assert html =~ "刷新通知列表"
    refute html =~ "重试标记已读"
  end

  test "renders a retry action when the user inbox fails" do
    html =
      render_component(&Notifications.menu/1, %{
        open: true,
        loading: false,
        notifications: [],
        unread_count: 0,
        error: "站内通知暂时无法读取，请重试",
        read_error: nil,
        selected: nil
      })

    assert html =~ ~s(role="alert")
    assert html =~ "站内通知暂时无法读取，请重试"
    assert html =~ ~s(phx-click="retry-notifications")
    refute html =~ "暂无站内通知"
  end

  test "renders a loading state before the user inbox finishes reading" do
    html =
      render_component(&Notifications.menu/1, %{
        open: true,
        loading: true,
        notifications: [],
        unread_count: 0,
        error: nil,
        read_error: nil,
        selected: nil
      })

    assert html =~ ~s(role="status")
    assert html =~ "正在读取通知"
    refute html =~ "暂无站内通知"
    refute html =~ "重试"
  end
end
