defmodule KeystonePhoenixWeb.NotificationControllerTest do
  use KeystonePhoenixWeb.ConnCase, async: false

  alias KeystonePhoenix.Auth
  alias KeystonePhoenix.Auth.ApiKey
  alias KeystonePhoenix.Auth.ApiKey.Key
  alias KeystonePhoenix.Authz.{SysPermission, SysRolePermission}
  alias KeystonePhoenix.Identity
  alias KeystonePhoenix.Notification
  alias KeystonePhoenix.Notification.SysNotification
  alias KeystonePhoenix.Repo
  alias KeystonePhoenix.Role.SysRole
  alias KeystonePhoenix.User.SysUser

  @key_permissions ~w(api-key:create api-key:read api-key:rotate api-key:revoke)

  @tag :integration
  test "HTTP inbox is private, supports idempotent reads, and rejects API Keys", %{conn: conn} do
    owner = create_user("notification_owner", @key_permissions)
    other = create_user("notification_other", @key_permissions)
    owner_token = login(owner)
    other_token = login(other)
    own_notification = Notification.create_api_key_event!(owner.user_id, :created)
    foreign_notification = Notification.create_api_key_event!(other.user_id, :created)

    inbox =
      conn
      |> bearer(owner_token)
      |> get("/api/v1/notifications")
      |> json_response(200)
      |> Map.fetch!("data")

    assert inbox["unreadCount"] == 1
    assert MapSet.new(Map.keys(inbox)) == MapSet.new(["items", "unreadCount"])
    assert [item] = inbox["items"]
    assert item["id"] == own_notification.id
    assert item["readAt"] == nil

    assert MapSet.new(Map.keys(item)) ==
             MapSet.new(["id", "type", "title", "content", "createdAt", "readAt"])

    detail =
      conn
      |> bearer(owner_token)
      |> get("/api/v1/notifications/#{own_notification.id}")
      |> json_response(200)
      |> Map.fetch!("data")

    assert detail == item

    foreign_detail =
      conn
      |> bearer(owner_token)
      |> get("/api/v1/notifications/#{foreign_notification.id}")

    missing_detail =
      conn
      |> bearer(owner_token)
      |> get("/api/v1/notifications/#{Identity.v7()}")

    assert foreign_detail.status == 404
    assert json_response(foreign_detail, 404) == json_response(missing_detail, 404)

    foreign_read =
      conn
      |> bearer(owner_token)
      |> post("/api/v1/notifications/#{foreign_notification.id}/read")

    missing_read =
      conn
      |> bearer(owner_token)
      |> post("/api/v1/notifications/#{Identity.v7()}/read")

    assert foreign_read.status == 404
    assert json_response(foreign_read, 404) == json_response(missing_read, 404)

    first_read =
      conn
      |> bearer(owner_token)
      |> post("/api/v1/notifications/#{own_notification.id}/read")
      |> json_response(200)
      |> Map.fetch!("data")

    assert first_read["id"] == own_notification.id
    assert is_binary(first_read["readAt"])

    second_read =
      conn
      |> bearer(owner_token)
      |> post("/api/v1/notifications/#{own_notification.id}/read")
      |> json_response(200)
      |> Map.fetch!("data")

    assert second_read == first_read

    refreshed_inbox =
      conn
      |> bearer(owner_token)
      |> get("/api/v1/notifications")
      |> json_response(200)
      |> Map.fetch!("data")

    assert refreshed_inbox["unreadCount"] == 0

    assert {:ok, key} = ApiKey.issue(other.user_id, "notification key", ["api-key:read"])

    rejected =
      conn
      |> Plug.Conn.put_req_header("authorization", "ApiKey #{key.api_key}")
      |> get("/api/v1/notifications")

    assert rejected.status == 403
    assert get_in(json_response(rejected, 403), ["error", "code"]) == "permission_denied"

    other_inbox =
      build_conn()
      |> bearer(other_token)
      |> get("/api/v1/notifications")
      |> json_response(200)
      |> Map.fetch!("data")

    other_ids = Enum.map(other_inbox["items"], & &1["id"])
    assert foreign_notification.id in other_ids
    refute own_notification.id in other_ids
    assert length(other_ids) == 2
  end

  @tag :integration
  test "inbox caps the page while counting every unread record" do
    user = create_user("notification_page", [])
    other = create_user("notification_page_other", [])
    base_time = DateTime.utc_now() |> DateTime.add(-60, :second)

    notifications =
      Enum.map(1..55, fn index ->
        read_at = if index <= 2, do: DateTime.add(base_time, index, :second), else: nil
        insert_notification(user.user_id, index, DateTime.add(base_time, index, :second), read_at)
      end)

    foreign = insert_notification(other.user_id, 56, base_time, nil)

    assert {:ok, %{items: items, unread_count: 53}} = Notification.list_for_user(user.user_id)

    assert length(items) == 50

    assert Enum.map(items, & &1["id"]) ==
             notifications |> Enum.drop(5) |> Enum.reverse() |> Enum.map(& &1.id)

    token = login(user)

    first =
      build_conn() |> bearer(token) |> get("/api/v1/notifications?page=1") |> json_response(200)

    second =
      build_conn() |> bearer(token) |> get("/api/v1/notifications?page=2") |> json_response(200)

    assert %{"items" => first_items, "page" => 1, "hasMore" => true, "unreadCount" => 53} =
             first["data"]

    assert %{"items" => second_items, "page" => 2, "hasMore" => false, "unreadCount" => 53} =
             second["data"]

    assert length(first_items) == 50
    refute Enum.any?(first_items ++ second_items, &(&1["id"] == foreign.id))

    assert Enum.map(second_items, & &1["id"]) ==
             notifications |> Enum.take(5) |> Enum.reverse() |> Enum.map(& &1.id)

    # 较早的未读通知仍能查看详情并标记已读。
    old_unread = Enum.find(second_items, &is_nil(&1["readAt"]))

    assert build_conn()
           |> bearer(token)
           |> get("/api/v1/notifications/#{old_unread["id"]}")
           |> json_response(200)

    assert build_conn()
           |> bearer(token)
           |> post("/api/v1/notifications/#{old_unread["id"]}/read")
           |> json_response(200)

    for page <- ["0", "-1", "abc", "1000001"] do
      response = build_conn() |> bearer(token) |> get("/api/v1/notifications?page=#{page}")
      assert get_in(json_response(response, 200), ["data", "page"]) == 1
    end
  end

  @tag :integration
  test "API Key issue, rotation, and first revoke add safe lifecycle notifications" do
    user = create_user("notification_lifecycle", @key_permissions)
    other = create_user("notification_lifecycle_other", @key_permissions)

    assert {:ok, issued} = ApiKey.issue(user.user_id, "lifecycle key", ["api-key:read"])
    issued_hash = Repo.get!(Key, issued.id).key_hash
    assert {:ok, rotated} = ApiKey.rotate(user.user_id, issued.id)
    rotated_hash = Repo.get!(Key, rotated.id).key_hash
    assert :ok = ApiKey.revoke(user.user_id, rotated.id)
    assert :ok = ApiKey.revoke(user.user_id, rotated.id)

    assert {:ok, %{items: items, unread_count: 3}} = Notification.list_for_user(user.user_id)

    assert Enum.map(items, & &1["type"]) |> Enum.sort() ==
             ~w(api_key.created api_key.revoked api_key.rotated)

    assert Enum.all?(items, fn item ->
             Enum.all?([item["title"], item["content"]], fn text ->
               not String.contains?(text, issued.api_key) and
                 not String.contains?(text, rotated.api_key) and
                 not String.contains?(text, issued_hash) and
                 not String.contains?(text, rotated_hash)
             end)
           end)

    created_notification = Enum.find(items, &(&1["type"] == "api_key.created"))
    assert created_notification["title"] == "API Key 已签发"
    assert created_notification["content"] == "一个 API Key 已成功签发。"
    assert created_notification["readAt"] == nil

    rotated_notification = Enum.find(items, &(&1["type"] == "api_key.rotated"))
    assert rotated_notification["title"] == "API Key 已轮换"
    assert rotated_notification["content"] == "一个 API Key 已轮换，旧密钥已失效。"

    revoked_notification = Enum.find(items, &(&1["type"] == "api_key.revoked"))
    assert revoked_notification["title"] == "API Key 已撤销"
    assert revoked_notification["content"] == "一个 API Key 已撤销。"

    assert {:ok, %{items: [], unread_count: 0}} = Notification.list_for_user(other.user_id)
  end

  defp create_user(suffix, permissions) do
    role = create_role(suffix, permissions)

    %SysUser{}
    |> SysUser.create_changeset(%{
      user_id: Identity.v7(),
      role_id: role.role_id,
      username: "#{suffix}_#{System.unique_integer([:positive])}",
      password: "Strong!123",
      status: 1
    })
    |> Repo.insert!()
  end

  defp create_role(_suffix, permissions) do
    role =
      %SysRole{}
      |> Ecto.Changeset.change(%{
        role_id: Identity.v7(),
        role_name: "Notif #{System.unique_integer([:positive])}",
        role_key: "notif_#{System.unique_integer([:positive])}",
        role_sort: 1,
        data_scope: "ALL",
        status: 1,
        deleted: false
      })
      |> Repo.insert!()

    Enum.each(permissions, fn permission ->
      entry = Repo.get_by!(SysPermission, permission: permission)
      Repo.insert!(%SysRolePermission{role_id: role.role_id, permission_id: entry.permission_id})
    end)

    role
  end

  defp insert_notification(user_id, index, created_at, read_at) do
    %SysNotification{}
    |> SysNotification.changeset(%{
      id: Identity.v7(),
      user_id: user_id,
      type: "test.record",
      title: "测试通知 #{index}",
      content: "通知内容 #{index}",
      created_at: created_at,
      read_at: read_at
    })
    |> Repo.insert!()
  end

  defp login(user) do
    assert {:ok, tokens} = Auth.login_plaintext(user.username, "Strong!123", true)
    tokens.token
  end

  defp bearer(conn, token),
    do: Plug.Conn.put_req_header(conn, "authorization", "Bearer #{token}")
end
