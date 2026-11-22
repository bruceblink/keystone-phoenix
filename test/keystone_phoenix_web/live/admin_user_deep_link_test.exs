defmodule KeystonePhoenixWeb.AdminUserDeepLinkTest do
  use KeystonePhoenixWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import KeystonePhoenixWeb.LiveAuthenticationTestSupport, only: [live_socket: 1]

  alias KeystonePhoenix.Auth
  alias KeystonePhoenix.Repo
  alias KeystonePhoenix.Identity
  alias KeystonePhoenix.Department.SysDept
  alias KeystonePhoenix.Post.SysPost
  alias KeystonePhoenix.Role.SysRole
  alias KeystonePhoenix.User.SysUser
  alias KeystonePhoenixWeb.Live.LoginEvents
  alias KeystonePhoenixWeb.Live.AdminEvents.Accounts
  alias KeystonePhoenixWeb.Live.AdminPages.Feedback

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

    # 同一面板切换筛选条件再返回时，页面必须按新地址重新读取数据。
    forward_url = "/users?" <> URI.encode_query(%{"users_username" => admin.username})
    render_patch(view, forward_url)

    forward_socket = live_socket(view)
    assert forward_socket.assigns.user_query == admin.username
    assert forward_socket.assigns.user_total == 1
    assert Enum.any?(forward_socket.assigns.user_rows, &(&1["username"] == admin.username))

    render_patch(view, url)
    returned_socket = live_socket(view)
    assert returned_socket.assigns.user_query == username_prefix
    assert returned_socket.assigns.user_display_name_query == display_name
    assert returned_socket.assigns.page_nums["users"] == 2
    assert returned_socket.assigns.user_total == 21

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
  test "刷新用户列表保留当前筛选和页码，并在失败后保留旧数据直到恢复", %{conn: conn} do
    role = Repo.get_by!(SysRole, role_key: "admin", deleted: false)
    admin = create_user(role, "user_refresh_admin")
    suffix = System.unique_integer([:positive])
    username_prefix = "user_refresh_match_#{suffix}_"
    display_name = "刷新用户 #{suffix}"
    matching_users = insert_matching_users(role, username_prefix, display_name)
    post = create_post("user_refresh_#{suffix}")

    # 登录账号也绑定岗位，覆盖 LiveView 事件认证时重新读取用户关联名称的路径。
    admin = admin |> Ecto.Changeset.change(post_id: post.post_id) |> Repo.update!()
    matching_users |> hd() |> Ecto.Changeset.change(post_id: post.post_id) |> Repo.update!()

    url = users_url(username_prefix, display_name, 2)
    {:ok, view, _html} = live(conn, url)
    render_submit(view, "login", %{"username" => admin.username, "password" => @password})

    initial = live_socket(view)
    assert initial.assigns.page_nums["users"] == 2
    assert initial.assigns.user_total == 21
    original_uri = initial.assigns.current_uri
    selected_id = initial.assigns.user_rows |> hd() |> Map.fetch!("userId")
    render_click(view, "toggle-user-selection", %{"user-id" => selected_id, "selected" => "true"})
    selected_socket = live_socket(view)
    previous_rows = selected_socket.assigns.user_rows

    Repo.query!("ALTER TABLE sys_user RENAME TO sys_user_unavailable")

    failed =
      try do
        {:noreply, failed_socket} = Accounts.handle_event("refresh-users", %{}, selected_socket)

        assert failed_socket.assigns.user_rows == previous_rows
        assert failed_socket.assigns.user_total == 21
        assert failed_socket.assigns.user_query == username_prefix
        assert failed_socket.assigns.user_display_name_query == display_name
        assert failed_socket.assigns.page_nums["users"] == 2
        assert failed_socket.assigns.selected_user_ids == [selected_id]
        assert failed_socket.assigns.current_uri == original_uri
        assert Feedback.message(failed_socket.assigns.user_feedback) == "用户列表刷新失败，请重试"
        failed_socket
      after
        Repo.query!("ALTER TABLE sys_user_unavailable RENAME TO sys_user")
      end

    create_user(role, "#{username_prefix}22", display_name)
    {:noreply, recovered} = Accounts.handle_event("refresh-users", %{}, failed)

    assert recovered.assigns.user_query == username_prefix
    assert recovered.assigns.user_display_name_query == display_name
    assert recovered.assigns.page_nums["users"] == 2
    assert recovered.assigns.user_total == 22
    assert length(recovered.assigns.user_rows) == 2

    assert Enum.all?(
             recovered.assigns.user_rows,
             &String.starts_with?(&1["username"], username_prefix)
           )

    assert recovered.assigns.selected_user_ids == [selected_id]
    assert recovered.assigns.current_uri == original_uri
    assert recovered.assigns.user_feedback == nil
  end

  @tag :integration
  test "岗位查询失败时仍拒绝权限版本、数据范围、停用和已撤销会话", _context do
    role = Repo.get_by!(SysRole, role_key: "admin", deleted: false)
    post = create_post("user_refresh_auth_#{System.unique_integer([:positive])}")

    [permission_user, scope_user, disabled_user, revoked_user] =
      Enum.map(~w(permission scope disabled revoked), fn suffix ->
        user = create_user(role, "user_refresh_auth_#{suffix}")
        user |> Ecto.Changeset.change(post_id: post.post_id) |> Repo.update!()
      end)

    views = %{
      permission: authenticated_users_view(permission_user),
      scope: authenticated_users_view(scope_user),
      disabled: authenticated_users_view(disabled_user),
      revoked: authenticated_users_view(revoked_user)
    }

    Repo.query!("ALTER TABLE sys_post RENAME TO sys_post_unavailable")

    try do
      permission_user
      |> Ecto.Changeset.change(permission_version: permission_user.permission_version + 1)
      |> Repo.update!()

      permission_html = render_click(views.permission, "refresh-users")
      assert is_nil(live_socket(views.permission).assigns.current_user)
      assert permission_html =~ "登录状态已失效，请重新登录"

      scope_role = Repo.get!(SysRole, role.role_id)
      scope_role |> Ecto.Changeset.change(data_scope: "SELF") |> Repo.update!()

      scope_html = render_click(views.scope, "refresh-users")
      assert is_nil(live_socket(views.scope).assigns.current_user)
      assert scope_html =~ "登录状态已失效，请重新登录"

      disabled_user |> Ecto.Changeset.change(status: 0) |> Repo.update!()
      disabled_html = render_click(views.disabled, "refresh-users")
      assert is_nil(live_socket(views.disabled).assigns.current_user)
      assert disabled_html =~ "登录状态已失效，请重新登录"

      Auth.logout(live_socket(views.revoked).assigns.refresh_token)
      revoked_html = render_click(views.revoked, "refresh-users")
      assert is_nil(live_socket(views.revoked).assigns.current_user)
      assert revoked_html =~ "登录状态已失效，请重新登录"
    after
      Repo.query!("ALTER TABLE sys_post_unavailable RENAME TO sys_post")
    end
  end

  @tag :integration
  test "刷新事件同步外部修改的基础资料并保留关联显示名称", %{conn: conn} do
    role = Repo.get_by!(SysRole, role_key: "admin", deleted: false)
    suffix = System.unique_integer([:positive])
    post = create_post("user_profile_sync_#{suffix}")
    dept = create_dept("资料同步部门 #{suffix}")

    user =
      create_user(role, "user_profile_sync_#{suffix}", "登录时名称")
      |> Ecto.Changeset.change(
        post_id: post.post_id,
        dept_id: dept.dept_id,
        avatar: "/profile/avatar/old-#{suffix}.png",
        email: "old-#{suffix}@example.com"
      )
      |> Repo.update!()

    {:ok, view, _html} = live(conn, "/users")
    render_submit(view, "login", %{"username" => user.username, "password" => @password})

    initial_user = live_socket(view).assigns.current_user
    assert initial_user["nickname"] == "登录时名称"
    assert initial_user["postName"] == post.post_name
    assert initial_user["deptName"] == dept.dept_name
    assert initial_user["roleName"] != ""

    user
    |> Ecto.Changeset.change(
      nickname: "外部更新名称",
      avatar: "/profile/avatar/new-#{suffix}.png",
      email: "new-#{suffix}@example.com",
      phone_number: "13800000000"
    )
    |> Repo.update!()

    render_click(view, "refresh-users")
    refreshed_user = live_socket(view).assigns.current_user

    assert refreshed_user["nickname"] == "外部更新名称"
    assert refreshed_user["avatar"] == "/profile/avatar/new-#{suffix}.png"
    assert refreshed_user["email"] == "new-#{suffix}@example.com"
    assert refreshed_user["phoneNumber"] == "13800000000"
    assert refreshed_user["postName"] == initial_user["postName"]
    assert refreshed_user["deptName"] == initial_user["deptName"]
    assert refreshed_user["roleName"] == initial_user["roleName"]
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
    Enum.map(1..21, &create_user(role, "#{username_prefix}#{&1}", display_name))
  end

  defp create_post(code) do
    %SysPost{post_id: Identity.v7()}
    |> SysPost.changeset(%{
      post_code: code,
      post_name: "岗位 #{code}",
      post_sort: 1,
      status: 1
    })
    |> Repo.insert!()
  end

  # 创建可供资料同步测试读取显示名称的部门记录。
  defp create_dept(name) do
    %SysDept{dept_id: Identity.v7()}
    |> SysDept.changeset(%{dept_name: name, ancestors: "", status: 1})
    |> Repo.insert!()
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

  # 通过真实登录表单创建带岗位关联的 LiveView 会话，覆盖认证钩子读取身份的路径。
  defp authenticated_users_view(user) do
    {:ok, view, _html} = Phoenix.LiveViewTest.live(Phoenix.ConnTest.build_conn(), "/users")

    Phoenix.LiveViewTest.render_submit(view, "login", %{
      "username" => user.username,
      "password" => @password
    })

    view
  end
end
