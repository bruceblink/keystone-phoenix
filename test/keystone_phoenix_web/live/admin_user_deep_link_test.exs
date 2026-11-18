defmodule KeystonePhoenixWeb.AdminUserDeepLinkTest do
  use KeystonePhoenixWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import KeystonePhoenixWeb.LiveAuthenticationTestSupport, only: [live_socket: 1]

  alias KeystonePhoenix.Repo
  alias KeystonePhoenix.Role.SysRole
  alias KeystonePhoenix.User.SysUser
  alias KeystonePhoenixWeb.Live.LoginEvents

  @password "Strong!123"

  @tag :integration
  test "登录后恢复用户筛选和第 2 页，并在读取失败时保留深链接", %{conn: conn} do
    role = Repo.get_by!(SysRole, role_key: "admin", deleted: false)
    admin = create_user(role, "user_deep_link_admin")
    suffix = System.unique_integer([:positive])
    username_prefix = "user_deep_link_match_#{suffix}_"
    display_name = "深链接用户 #{suffix}"
    insert_matching_users(role, username_prefix, display_name)

    url = users_url(username_prefix, display_name, 2)
    {:ok, view, _html} = live(conn, url)

    render_submit(view, "login", %{"username" => admin.username, "password" => @password})

    socket = live_socket(view)
    assert socket.assigns.active_panel == "users"
    assert socket.assigns.user_query == username_prefix
    assert socket.assigns.user_display_name_query == display_name
    assert socket.assigns.page_nums["users"] == 2
    assert socket.assigns.user_total == 21
    assert length(socket.assigns.user_rows) == 1
    assert socket.assigns.user_rows |> List.first() |> Map.fetch!("username") =~ username_prefix

    original_uri = socket.assigns.current_uri
    previous_socket = %{socket | assigns: Map.put(socket.assigns, :current_user, nil)}
    Repo.query!("ALTER TABLE sys_user RENAME TO sys_user_unavailable")

    try do
      assert {:noreply, failed_socket} =
               LoginEvents.restore_route_after_login({:noreply, socket}, previous_socket)

      assert failed_socket.assigns.active_panel == "users"
      assert failed_socket.assigns.current_uri == original_uri
      assert failed_socket.assigns.page_nums["users"] == 2
      assert failed_socket.assigns.user_feedback
    after
      Repo.query!("ALTER TABLE sys_user_unavailable RENAME TO sys_user")
    end
  end

  @tag :integration
  test "没有用户列表权限时登录回到个人资料页", %{conn: conn} do
    user = create_user(nil, "user_deep_link_common")
    {:ok, view, _html} = live(conn, "/users?users_username=private_query")

    render_submit(view, "login", %{"username" => user.username, "password" => @password})

    socket = live_socket(view)
    assert socket.assigns.active_panel == "profile"
    assert URI.parse(socket.assigns.current_uri).path == "/profile"
    assert socket.assigns.user_rows == []
    assert socket.assigns.user_query == ""
    refute has_element?(view, ".monitor-page")
  end

  @tag :integration
  test "首次改密后仍需登录，第二次登录恢复原用户深链接", %{conn: conn} do
    role = Repo.get_by!(SysRole, role_key: "admin", deleted: false)
    user = create_user(role, "user_deep_link_password")
    user = user |> Ecto.Changeset.change(must_change_password: true) |> Repo.update!()
    {:ok, view, _html} = live(conn, "/users?users_username=after_password_change")

    render_submit(view, "login", %{"username" => user.username, "password" => @password})
    assert has_element?(view, "#initial-password-form")

    render_submit(view, "change-initial-password", %{
      "currentPassword" => @password,
      "newPassword" => "Changed!2026",
      "confirmPassword" => "Changed!2026"
    })

    assert has_element?(view, "#login-form")
    assert is_nil(live_socket(view).assigns.current_user)
    assert URI.parse(live_socket(view).assigns.current_uri).path == "/users"

    render_submit(view, "login", %{
      "username" => user.username,
      "password" => "Changed!2026"
    })

    assert live_socket(view).assigns.active_panel == "users"
    assert live_socket(view).assigns.user_query == "after_password_change"
  end

  defp insert_matching_users(role, username_prefix, display_name) do
    for index <- 1..21 do
      create_user(role, "#{username_prefix}#{index}", display_name)
    end
  end

  defp create_user(role, suffix, display_name \\ "深链接管理员") do
    %SysUser{}
    |> SysUser.create_changeset(%{
      "username" => suffix,
      "nickname" => display_name,
      "password" => @password,
      "role_id" => role && role.role_id,
      "status" => 1
    })
    |> Repo.insert!()
  end

  defp users_url(username, display_name, page) do
    query =
      URI.encode_query(%{
        "users_username" => username,
        "users_displayName" => display_name,
        "users_page" => page
      })

    "/users?#{query}"
  end
end
