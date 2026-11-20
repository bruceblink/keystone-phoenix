defmodule KeystonePhoenixWeb.UserNotificationsLiveTest do
  use KeystonePhoenixWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias KeystonePhoenix.Identity
  alias KeystonePhoenix.Auth.ApiKey
  alias KeystonePhoenix.Auth.ApiKey.Key
  alias KeystonePhoenix.Notification
  alias KeystonePhoenix.Notification.SysNotification
  alias KeystonePhoenix.Notice.SysNotice
  alias KeystonePhoenix.Repo
  alias KeystonePhoenix.Role.SysRole
  alias KeystonePhoenix.User.SysUser
  alias KeystonePhoenixWeb.LiveAuthenticationTestSupport, as: LiveSupport
  alias KeystonePhoenixWeb.Live.AdminPages.Notifications, as: NotificationMenu

  @password "Strong!123"

  @tag :integration
  test "expired API Key displays its actual state and cannot be rotated", %{conn: conn} do
    # 使用真实存储和 LiveView 验证过期状态与后端筛选一致。
    role = Repo.get_by!(SysRole, role_key: "admin", deleted: false)
    owner = create_user(role, "expired_key_owner")
    assert {:ok, issued} = ApiKey.issue(owner.user_id, "expired live key", ["api-key:read"])

    issued.id
    |> then(&Repo.get!(Key, &1))
    |> Ecto.Changeset.change(expires_at: DateTime.add(DateTime.utc_now(), -60, :second))
    |> Repo.update!()

    {:ok, view, _html} = live(conn, "/")
    login(view, owner)
    render_click(view, "show-panel", %{"panel" => "api-keys"})

    assert has_element?(view, "tr", "已过期")

    assert has_element?(
             view,
             "button[phx-click='rotate-api-key'][phx-value-id='#{issued.id}'][disabled]"
           )

    assert has_element?(view, "button[phx-click='revoke-api-key'][phx-value-id='#{issued.id}']")
    render_click(view, "filter-api-keys", %{"query" => "expired live key", "status" => "active"})
    assert LiveSupport.live_socket(view).assigns.api_key_total == 0
  end

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
    assert has_element?(view, ".notification-dot")
    assert has_element?(view, "button[aria-label='通知，1 条未读']")
    render_click(view, "toggle-notifications")
    owner_html = render_async(view)

    assert owner_html =~ own_notification.title
    refute owner_html =~ other_notification.title
    refute owner_html =~ announcement.notice_title
    assert has_element?(view, ".notification-dot")

    render_click(view, "open-notification", %{"notification-id" => own_notification.id})
    assert has_element?(view, ".notification-detail h3", own_notification.title)
    assert LiveSupport.live_socket(view).assigns.notifications_unread_count == 0
    assert Repo.get!(KeystonePhoenix.Notification.SysNotification, own_notification.id).read_at
    refute has_element?(view, ".notification-dot")

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

  # 站内通知轮询须保留详情、旧列表和注销后的会话边界。
  @tag :integration
  test "refreshes the badge and open inbox on the notification timer", %{conn: conn} do
    role = Repo.get_by!(SysRole, role_key: "admin", deleted: false)
    owner = create_user(role, "inbox_timer")
    first = Notification.create_api_key_event!(owner.user_id, :created)

    {:ok, view, _html} = live(conn, "/")
    login(view, owner)

    token = LiveSupport.live_socket(view).assigns.notifications_refresh_token
    assert is_reference(token)

    send(view.pid, {:notifications_refresh_tick, token})
    render(view)

    assert LiveSupport.live_socket(view).assigns.notifications_unread_count == 1
    assert has_element?(view, "button[aria-label='通知，1 条未读']")

    render_click(view, "toggle-notifications")
    render_async(view)
    assert has_element?(view, ".notification-list-item", first.title)
    render_click(view, "open-notification", %{"notification-id" => first.id})
    assert has_element?(view, ".notification-detail h3", first.title)

    second = Notification.create_api_key_event!(owner.user_id, :rotated)
    next_token = LiveSupport.live_socket(view).assigns.notifications_refresh_token
    assert is_reference(next_token)
    refute next_token == token

    send(view.pid, {:notifications_refresh_tick, next_token})
    render(view)

    assert LiveSupport.live_socket(view).assigns.notifications_unread_count == 1
    assert has_element?(view, ".notification-detail h3", first.title)
    assert length(LiveSupport.live_socket(view).assigns.in_app_notifications) == 1

    render_click(view, "back-notifications")
    refreshed_html = render_async(view)

    assert refreshed_html =~ second.title
    assert length(LiveSupport.live_socket(view).assigns.in_app_notifications) == 2
    refute LiveSupport.live_socket(view).assigns.selected_notification_id

    Repo.query!("ALTER TABLE sys_user_notification RENAME TO sys_user_notification_unavailable")

    try do
      stale_data = LiveSupport.live_socket(view).assigns.in_app_notifications
      stale_count = LiveSupport.live_socket(view).assigns.notifications_unread_count
      stale_token = LiveSupport.live_socket(view).assigns.notifications_refresh_token

      send(view.pid, {:notifications_refresh_tick, stale_token})
      failed_html = render_async(view)

      assert failed_html =~ "无法读取站内通知"
      assert has_element?(view, ".notification-state-error[role='alert']", "无法读取站内通知")
      assert has_element?(view, ".notification-list-item", second.title)
      assert LiveSupport.live_socket(view).assigns.in_app_notifications == stale_data
      assert LiveSupport.live_socket(view).assigns.notifications_unread_count == stale_count
    after
      Repo.query!("ALTER TABLE sys_user_notification_unavailable RENAME TO sys_user_notification")
    end

    render_click(view, "retry-notifications")
    render_async(view)
    assert LiveSupport.live_socket(view).assigns.notifications_error == nil

    stale_token = LiveSupport.live_socket(view).assigns.notifications_refresh_token
    render_click(view, "logout")
    assert LiveSupport.live_socket(view).assigns.notifications_refresh_timer == nil
    assert LiveSupport.live_socket(view).assigns.notifications_refresh_token == nil

    send(view.pid, {:notifications_refresh_tick, stale_token})
    render(view)

    assert LiveSupport.live_socket(view).assigns.current_user == nil
    assert LiveSupport.live_socket(view).assigns.notifications_unread_count == 0
    assert LiveSupport.live_socket(view).assigns.notifications_refresh_timer == nil
  end

  # 用真实 LiveView 状态和数据库分页结果验证迟到响应不会关闭详情。
  @tag :integration
  test "keeps a selected notification when opening it during a page refresh", %{conn: conn} do
    role = Repo.get_by!(SysRole, role_key: "admin", deleted: false)
    owner = create_user(role, "inbox_refresh_detail")

    base_time =
      DateTime.utc_now()
      |> DateTime.add(-60, :second)
      |> DateTime.truncate(:microsecond)

    notifications =
      for index <- 1..50 do
        %SysNotification{}
        |> SysNotification.changeset(%{
          id: Identity.v7(),
          user_id: owner.user_id,
          type: "test.refresh-detail",
          title: "后台刷新通知 #{index}",
          content: "后台刷新时保持已选通知详情。",
          created_at: DateTime.add(base_time, index, :second)
        })
        |> Repo.insert!()
      end

    oldest = hd(notifications)
    {:ok, view, _html} = live(conn, "/")
    login(view, owner)
    render_click(view, "toggle-notifications")
    render_async(view)
    assert has_element?(view, ".notification-list-item", oldest.title)

    Notification.create_api_key_event!(owner.user_id, :rotated)
    assert {:ok, shifted_page} = Notification.list_for_user(owner.user_id, 1)
    refute Enum.any?(shifted_page.items, &(&1["id"] == oldest.id))

    async_name = {:user_notifications, owner.user_id, 1, make_ref()}

    socket =
      LiveSupport.live_socket(view)
      |> Phoenix.Component.assign(
        notifications_loading: true,
        notifications_async_name: async_name
      )

    {:noreply, selected_socket} =
      KeystonePhoenixWeb.LoginNotifications.open(
        %{"notification-id" => oldest.id},
        socket
      )

    assert selected_socket.assigns.notifications_loading == false
    assert selected_socket.assigns.notifications_async_name == nil
    assert selected_socket.assigns.selected_notification_id == oldest.id

    {:noreply, final_socket} =
      KeystonePhoenixWeb.LoginNotifications.handle_async(
        async_name,
        {:ok, {owner.user_id, 1, {:ok, shifted_page}}},
        selected_socket
      )

    selected =
      KeystonePhoenixWeb.LoginNotifications.selected(
        final_socket.assigns.in_app_notifications,
        final_socket.assigns.selected_notification_id
      )

    menu_html =
      render_component(&NotificationMenu.menu/1, %{
        open: true,
        loading: final_socket.assigns.notifications_loading,
        notifications: final_socket.assigns.in_app_notifications,
        unread_count: final_socket.assigns.notifications_unread_count,
        page: final_socket.assigns.notifications_page,
        has_more: final_socket.assigns.notifications_has_more,
        error: nil,
        selected: selected
      })

    assert selected["title"] == oldest.title
    assert menu_html =~ "<h3>#{oldest.title}</h3>"
  end

  @tag :integration
  test "changes notification pages and preserves the unread count across page errors", %{
    conn: conn
  } do
    role = Repo.get_by!(SysRole, role_key: "admin", deleted: false)
    owner = create_user(role, "inbox_paged")
    base_time = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    for index <- 1..55 do
      read_at = if index <= 2, do: DateTime.add(base_time, index, :second), else: nil

      %SysNotification{}
      |> SysNotification.changeset(%{
        id: Identity.v7(),
        user_id: owner.user_id,
        type: "test.page",
        title: "分页站内通知 #{index}",
        content: "第 #{index} 条通知内容。",
        created_at: DateTime.add(base_time, index, :second),
        read_at: read_at
      })
      |> Repo.insert!()
    end

    {:ok, view, _html} = live(conn, "/")
    login(view, owner)
    render_click(view, "toggle-notifications")
    page_one_html = render_async(view)

    assert length(LiveSupport.live_socket(view).assigns.in_app_notifications) == 50
    assert LiveSupport.live_socket(view).assigns.notifications_unread_count == 53
    assert LiveSupport.live_socket(view).assigns.notifications_has_more
    assert page_one_html =~ "分页站内通知 55"

    refute Enum.any?(
             LiveSupport.live_socket(view).assigns.in_app_notifications,
             &(&1["title"] == "分页站内通知 1")
           )

    assert page_one_html =~ "50 条本页通知 · 第 1 页"

    assert has_element?(
             view,
             "button[phx-click='paginate-notifications'][phx-value-page='0'][disabled]"
           )

    assert has_element?(
             view,
             "button[phx-click='paginate-notifications'][phx-value-page='2']:not([disabled])"
           )

    Repo.query!("ALTER TABLE sys_user_notification RENAME TO sys_user_notification_unavailable")

    try do
      render_click(view, "paginate-notifications", %{"page" => "2"})
      failed_page_html = render_async(view)

      assert failed_page_html =~ "无法读取站内通知"
      assert has_element?(view, "button[phx-click='retry-notifications']", "重试")

      assert has_element?(
               view,
               "button[phx-click='paginate-notifications'][phx-value-page='1']:not([disabled])"
             )

      assert has_element?(
               view,
               "button[phx-click='paginate-notifications'][phx-value-page='3'][disabled]"
             )

      assert LiveSupport.live_socket(view).assigns.in_app_notifications == []
      assert LiveSupport.live_socket(view).assigns.notifications_page == 2
      assert LiveSupport.live_socket(view).assigns.notifications_error
    after
      Repo.query!("ALTER TABLE sys_user_notification_unavailable RENAME TO sys_user_notification")
    end

    render_click(view, "retry-notifications")
    page_two_html = render_async(view)

    assert length(LiveSupport.live_socket(view).assigns.in_app_notifications) == 5
    assert LiveSupport.live_socket(view).assigns.notifications_page == 2
    assert LiveSupport.live_socket(view).assigns.notifications_has_more == false
    assert LiveSupport.live_socket(view).assigns.notifications_unread_count == 53
    assert page_two_html =~ "5 条本页通知 · 第 2 页"

    assert Enum.any?(
             LiveSupport.live_socket(view).assigns.in_app_notifications,
             &(&1["title"] == "分页站内通知 1")
           )

    assert page_two_html =~ "分页站内通知 1</strong>"

    notification =
      Enum.find(
        LiveSupport.live_socket(view).assigns.in_app_notifications,
        &(&1["title"] == "分页站内通知 1")
      )

    render_click(view, "open-notification", %{"notification-id" => notification["id"]})
    assert has_element?(view, ".notification-detail h3", "分页站内通知 1")
    refute has_element?(view, ".notification-pagination")
    render_click(view, "back-notifications")
    render_async(view)
    assert has_element?(view, ".notification-pagination", "第 2 页")
    assert length(LiveSupport.live_socket(view).assigns.in_app_notifications) == 5

    render_click(view, "paginate-notifications", %{"page" => "1"})
    render_async(view)
    assert LiveSupport.live_socket(view).assigns.notifications_page == 1
    assert length(LiveSupport.live_socket(view).assigns.in_app_notifications) == 50
    assert LiveSupport.live_socket(view).assigns.notifications_unread_count == 53
  end

  @tag :integration
  test "API Key lifecycle actions refresh the unread badge immediately", %{conn: conn} do
    role = Repo.get_by!(SysRole, role_key: "admin", deleted: false)
    user = create_user(role, "inbox_key_events")

    {:ok, view, _html} = live(conn, "/")
    login(view, user)
    assert LiveSupport.live_socket(view).assigns.notifications_unread_count == 0
    refresh_token = LiveSupport.live_socket(view).assigns.notifications_refresh_token
    assert is_reference(refresh_token)

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
    issue_failures = [
      {" ", DateTime.to_iso8601(expires_at), "api_key_name_invalid",
       "API Key 名称必须为 1 到 128 个字符。"},
      {String.duplicate("a", 129), DateTime.to_iso8601(expires_at), "api_key_name_invalid",
       "API Key 名称必须为 1 到 128 个字符。"},
      {"invalid expiry", "invalid", "api_key_expiry_invalid", "API Key 到期时间格式无效，请重新选择时间。"},
      {"out of range", DateTime.to_iso8601(too_late), "api_key_expiry_out_of_range",
       "API Key 到期时间必须晚于当前时间且不超过 90 天。"}
    ]

    for {name, expiry_value, expected_code, expected_message} <- issue_failures do
      submit_api_key_issue(view, name, expiry_value, expires_at_local)

      assert has_element?(
               view,
               "#api-key-modal #api-key-form-feedback[role='alert']",
               expected_message
             )

      assert has_element?(view, "#api-key-form[aria-describedby='api-key-form-feedback']")
      assert has_element?(view, "#api-key-form-feedback", "错误码：#{expected_code}")
      assert LiveSupport.live_socket(view).assigns.api_key_form["name"] == name
      assert LiveSupport.live_socket(view).assigns.active_modal == "api-key"
      refute has_element?(view, "#api-key-feedback")
      assert LiveSupport.live_socket(view).assigns.issued_api_key == nil
    end

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
    assert has_element?(view, ".notification-dot")

    render_click(view, "rotate-api-key", %{"id" => issued.id})
    rotated = LiveSupport.live_socket(view).assigns.issued_api_key
    assert LiveSupport.live_socket(view).assigns.notifications_unread_count == 2
    assert has_element?(view, ".notification-dot")
    assert has_element?(view, "button[aria-label='通知，2 条未读']")

    render_click(view, "revoke-api-key", %{"id" => rotated.id})
    assert LiveSupport.live_socket(view).assigns.notifications_unread_count == 3
    assert has_element?(view, ".notification-dot")
    assert has_element?(view, "button[aria-label='通知，3 条未读']")
    assert LiveSupport.live_socket(view).assigns.notifications_refresh_token == refresh_token
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
      notice_type: "announcement",
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

  defp submit_api_key_issue(view, name, expiry, local_expiry) do
    params = %{
      "name" => name,
      "expiresAt" => expiry,
      "expiresAtLocal" => local_expiry,
      "scopes" => "api-key:read",
      "scopeQuery" => ""
    }

    render_change(view, "filter-api-key-scopes", params)
    render_submit(view, "save-api-key", Map.drop(params, ["scopeQuery"]))
  end
end
