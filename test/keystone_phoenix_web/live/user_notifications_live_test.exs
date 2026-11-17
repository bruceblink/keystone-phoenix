defmodule KeystonePhoenixWeb.UserNotificationsLiveTest do
  use KeystonePhoenixWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias KeystonePhoenix.Identity
  alias KeystonePhoenix.Notification
  alias KeystonePhoenix.Notice.SysNotice
  alias KeystonePhoenix.Repo
  alias KeystonePhoenix.Role.SysRole
  alias KeystonePhoenix.User.SysUser
  alias KeystonePhoenixWeb.LiveAuthenticationTestSupport, as: LiveSupport

  @password "Strong!123"

  @tag :integration
  test "bell shows only the active user's inbox and marks a selected item read", %{conn: conn} do
    role = Repo.get_by!(SysRole, role_key: "admin", deleted: false)
    owner = create_user(role, "inbox_owner")
    other = create_user(role, "inbox_other")
    own_notification = Notification.create_api_key_event!(owner.user_id, :created)
    other_notification = Notification.create_api_key_event!(other.user_id, :rotated)
    announcement = create_public_announcement()

    {:ok, view, _html} = live(conn, "/")
    login(view, owner)

    assert LiveSupport.live_socket(view).assigns.in_app_notifications == []
    assert LiveSupport.live_socket(view).assigns.notifications_unread_count == 1
    assert has_element?(view, ".notification-count", "1")
    render_click(view, "toggle-notifications")
    owner_html = render_async(view)

    assert owner_html =~ own_notification.title
    refute owner_html =~ other_notification.title
    refute owner_html =~ announcement.notice_title
    assert has_element?(view, ".notification-count", "1")

    render_click(view, "open-notification", %{"notification-id" => own_notification.id})
    assert has_element?(view, ".notification-detail h3", own_notification.title)
    assert LiveSupport.live_socket(view).assigns.notifications_unread_count == 0
    assert Repo.get!(KeystonePhoenix.Notification.SysNotification, own_notification.id).read_at
    refute has_element?(view, ".notification-count")

    render_click(view, "logout")
    login(view, other)
    assert LiveSupport.live_socket(view).assigns.in_app_notifications == []
    render_click(view, "toggle-notifications")
    other_html = render_async(view)

    assert other_html =~ other_notification.title
    refute other_html =~ own_notification.title
    refute other_html =~ announcement.notice_title

    render_click(view, "open-notification", %{"notification-id" => own_notification.id})
    assert is_nil(LiveSupport.live_socket(view).assigns.selected_notification_id)
    refute render(view) =~ own_notification.content
  end

  @tag :integration
  test "API Key lifecycle actions refresh the unread badge immediately", %{conn: conn} do
    role = Repo.get_by!(SysRole, role_key: "admin", deleted: false)
    user = create_user(role, "inbox_key_events")

    {:ok, view, _html} = live(conn, "/")
    login(view, user)
    assert LiveSupport.live_socket(view).assigns.notifications_unread_count == 0

    render_click(view, "show-panel", %{"panel" => "api-keys"})
    render_click(view, "new-api-key")

    assert has_element?(view, "#api-key-form[phx-hook='LocalDateTimeInput']")
    assert has_element?(view, "#api-key-expires-local[name='expiresAtLocal']")

    assert has_element?(view, "#api-key-expires-utc[name='expiresAt']")

    expiry_minute =
      DateTime.utc_now()
      |> DateTime.add(30 * 24 * 60 * 60)
      |> DateTime.to_naive()

    expires_at =
      expiry_minute
      |> then(&%{&1 | second: 0, microsecond: {0, 0}})
      |> DateTime.from_naive!("Etc/UTC")

    expires_at_local =
      expires_at |> DateTime.add(8 * 60 * 60) |> Calendar.strftime("%Y-%m-%dT%H:%M")

    render_change(view, "filter-api-key-scopes", %{
      "name" => "inbox lifecycle",
      "expiresAt" => DateTime.to_iso8601(expires_at),
      "expiresAtLocal" => expires_at_local,
      "scopes" => "",
      "scopeQuery" => "api-key"
    })

    render_click(view, "toggle-api-key-scope", %{
      "scope" => "api-key:read",
      "selected" => "true"
    })

    assert LiveSupport.live_socket(view).assigns.api_key_form["expiresAt"] ==
             DateTime.to_iso8601(expires_at)

    assert LiveSupport.live_socket(view).assigns.api_key_form["expiresAtLocal"] ==
             expires_at_local

    too_late = DateTime.add(DateTime.utc_now(), 91 * 24 * 60 * 60, :second)

    # LiveView 应显示到期规则和已有业务码，并保留签发弹窗供用户修正。
    render_submit(view, "save-api-key", %{
      "name" => "out of range",
      "scopes" => "api-key:read",
      "expiresAt" => DateTime.to_iso8601(too_late)
    })

    assert has_element?(
             view,
             "#api-key-modal #api-key-form-feedback[role='alert']",
             "到期时间必须晚于当前时间且不超过 90 天"
           )

    assert has_element?(view, "#api-key-form[aria-describedby='api-key-form-feedback']")
    assert has_element?(view, "#api-key-form-feedback", "错误码：validation_failed")
    refute has_element?(view, "#api-key-feedback")
    assert LiveSupport.live_socket(view).assigns.issued_api_key == nil

    render_submit(view, "save-api-key", %{
      "name" => "inbox lifecycle",
      "scopes" => "api-key:read",
      "expiresAt" => DateTime.to_iso8601(expires_at)
    })

    issued = LiveSupport.live_socket(view).assigns.issued_api_key
    assert is_binary(issued.api_key)
    assert DateTime.compare(issued.expires_at, expires_at) == :eq
    assert has_element?(view, "#api-key-feedback[role='status']", "API Key 已签发")
    refute has_element?(view, "#api-key-form-feedback")
    assert LiveSupport.live_socket(view).assigns.notifications_unread_count == 1
    assert has_element?(view, ".notification-count", "1")

    render_click(view, "rotate-api-key", %{"id" => issued.id})
    rotated = LiveSupport.live_socket(view).assigns.issued_api_key
    assert LiveSupport.live_socket(view).assigns.notifications_unread_count == 2
    assert has_element?(view, ".notification-count", "2")

    render_click(view, "revoke-api-key", %{"id" => rotated.id})
    assert LiveSupport.live_socket(view).assigns.notifications_unread_count == 3
    assert has_element?(view, ".notification-count", "3")
  end

  @tag :integration
  test "keeps a missing notification visible and refreshes the list on request", %{conn: conn} do
    role = Repo.get_by!(SysRole, role_key: "admin", deleted: false)
    owner = create_user(role, "inbox_retry")
    notification = Notification.create_api_key_event!(owner.user_id, :created)

    {:ok, view, _html} = live(conn, "/")
    login(view, owner)
    render_click(view, "toggle-notifications")
    render_async(view)

    Repo.delete!(Repo.get!(KeystonePhoenix.Notification.SysNotification, notification.id))
    render_click(view, "open-notification", %{"notification-id" => notification.id})

    assert has_element?(view, ".notification-detail h3", notification.title)
    assert has_element?(view, ".notification-detail", notification.content)
    assert has_element?(view, ".notification-detail [role='alert']", "通知不存在或已移除")
    assert has_element?(view, "button[phx-click='retry-notifications']", "刷新通知列表")
    assert LiveSupport.live_socket(view).assigns.selected_notification_id == notification.id

    render_click(view, "retry-notifications")
    refreshed_html = render_async(view)

    assert refreshed_html =~ "暂无站内通知"
    refute has_element?(view, ".notification-detail")
    refute has_element?(view, ".notification-detail [role='alert']")
    assert is_nil(LiveSupport.live_socket(view).assigns.selected_notification_id)
    assert LiveSupport.live_socket(view).assigns.notifications_unread_count == 0
  end

  defp create_user(role, suffix) do
    %SysUser{}
    |> SysUser.create_changeset(%{
      user_id: Identity.v7(),
      role_id: role.role_id,
      username: "#{suffix}_#{System.unique_integer([:positive])}",
      password: @password,
      status: 1
    })
    |> Repo.insert!()
  end

  defp create_public_announcement do
    %SysNotice{}
    |> SysNotice.changeset(%{
      notice_title: "公开公告-不进入个人收件箱",
      notice_type: 2,
      notice_content: "公告和个人站内通知使用不同数据源。",
      status: 1
    })
    |> Ecto.Changeset.put_change(:published, true)
    |> Ecto.Changeset.put_change(:publish_at, DateTime.utc_now())
    |> Repo.insert!()
  end

  defp login(view, user) do
    render_submit(view, "login", %{"username" => user.username, "password" => @password})
    refute has_element?(view, "#login-form")
  end
end
