defmodule KeystonePhoenixWeb.AdminRoleAuthorizationTest do
  use KeystonePhoenixWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias KeystonePhoenix.{Auth, Identity, Repo}
  alias KeystonePhoenix.Auth.Mfa
  alias KeystonePhoenix.Auth.Mfa.Totp
  alias KeystonePhoenix.Authz.{PolicyCache, SysPermission, SysRolePermission}
  alias KeystonePhoenix.Menu.SysMenu
  alias KeystonePhoenix.Role.{Permissions, SysRole, SysRoleMenu}
  alias KeystonePhoenix.User.{SysUser, SysUserRole}
  alias KeystonePhoenixWeb.Live.AdminPages.Feedback

  # 无 role:manage 时验证元数据不会进入页面表单，也不会被伪造参数覆盖。
  test "role update can change basic fields without submitting or replacing metadata", %{
    conn: conn
  } do
    {actor, actor_role} = create_actor(["role:read", "role:update"])
    role = create_role("role metadata target", "CUSTOM", "17,23", ["user:read"])
    menu = create_menu_for_role(role)
    {:ok, member_candidate} = create_user(actor_role, "role member candidate")
    {:ok, view} = login_with_step_up(conn, actor)
    render_click(view, "show-panel", %{"panel" => "roles"})

    assert has_element?(view, "button[phx-click='edit-role']")
    refute has_element?(view, "button[phx-click='new-role']")
    refute has_element?(view, "button[phx-click='open-role-delete']")
    refute has_element?(view, "button[phx-click='open-role-permissions']")

    render_click(view, "toggle-role-selection", %{
      "role-id" => to_string(role.role_id),
      "selected" => "true"
    })

    assert live_socket(view).assigns.selected_role_ids == []
    render_click(view, "edit-role", %{"role-id" => to_string(role.role_id)})

    assert has_element?(view, "#role-metadata-preserved")
    refute has_element?(view, "#role-modal input[name='dataScope']")
    refute has_element?(view, "#role-modal input[name='deptIdSet']")
    refute has_element?(view, "#role-modal input[name='permissions']")
    refute has_element?(view, "#role-modal select[name='menuIds[]']")

    render_submit(view, "save-role", %{
      "roleId" => to_string(role.role_id),
      "roleName" => "role metadata updated",
      "roleKey" => role.role_key,
      "roleSort" => "1",
      "status" => "1",
      "dataScope" => "ALL",
      "deptIdSet" => "",
      "permissions" => "role:manage",
      "menuIds[]" => [to_string(menu.menu_id)]
    })

    saved = Repo.get!(SysRole, role.role_id)
    assert saved.role_name == "role metadata updated"
    assert saved.data_scope == "CUSTOM"
    assert saved.dept_id_set == "17,23"
    assert Permissions.list(role.role_id) == ["user:read"]
    assert Repo.get_by!(SysRoleMenu, role_id: role.role_id, menu_id: menu.menu_id)

    render_click(view, "select-role", %{"role-id" => to_string(role.role_id)})
    render_click(view, "assign-role-user", %{"user-id" => to_string(member_candidate.user_id)})

    assert Repo.get_by(SysUserRole, role_id: role.role_id, user_id: member_candidate.user_id) ==
             nil

    render_submit(view, "delete-role", %{"role-id" => to_string(role.role_id)})
    refute Repo.get!(SysRole, role.role_id).deleted
  end

  # 创建权限独立于更新权限，表单不包含角色元数据输入。
  test "role:create works without role:update or role:manage", %{conn: conn} do
    {actor, _actor_role} = create_actor(["role:read", "role:create"])
    {:ok, view} = login_with_step_up(conn, actor)
    render_click(view, "show-panel", %{"panel" => "roles"})

    assert has_element?(view, "button[phx-click='new-role']")
    refute has_element?(view, "button[phx-click='edit-role']")
    render_click(view, "new-role")
    refute has_element?(view, "#role-modal select[name='dataScope']")

    render_submit(view, "save-role", %{
      "roleId" => "",
      "roleName" => "created without metadata",
      "roleKey" => unique("role_create_only"),
      "roleSort" => "2",
      "status" => "1"
    })

    assert Repo.get_by!(SysRole, role_name: "created without metadata").data_scope == "ALL"
  end

  # role:manage 提供独立权限入口，不依赖 role:update。
  test "role:manage configures permissions without role:update and preserves other metadata", %{
    conn: conn
  } do
    {actor, _actor_role} = create_actor(["role:read", "role:manage"])
    role = create_role("permission only target", "CUSTOM", "31,37", [])
    menu = create_menu_for_role(role)
    {:ok, view} = login_with_step_up(conn, actor)
    render_click(view, "show-panel", %{"panel" => "roles"})

    refute has_element?(view, "button[phx-click='edit-role']")
    assert has_element?(view, "button[phx-click='open-role-permissions']")
    render_click(view, "open-role-permissions", %{"role-id" => to_string(role.role_id)})
    assert has_element?(view, "#role-permissions-modal")
    assert has_element?(view, "#role-permissions-modal input[phx-value-permission='role:read']")

    render_click(view, "toggle-role-permission", %{
      "permission" => "role:read",
      "selected" => "true"
    })

    render_click(view, "toggle-role-permission", %{
      "permission" => "user:delete",
      "selected" => "true"
    })

    assert live_socket(view).assigns.role_permissions_form["permissions"] == "role:read"
    html = render_submit(view, "save-role-permissions", %{"roleId" => Identity.v7()})

    assert Permissions.list(role.role_id) == ["role:read"]

    refreshed_role =
      Enum.find(live_socket(view).assigns.role_page_rows, &(&1["roleId"] == role.role_id))

    assert refreshed_role["permissionCount"] == 1

    role_row =
      html
      |> String.split("<tr>")
      |> Enum.find(&String.contains?(&1, "permission only target"))
      |> String.split("</tr>")
      |> hd()

    assert role_row =~ "<td>1</td>"

    saved = Repo.get!(SysRole, role.role_id)
    assert saved.data_scope == "CUSTOM"
    assert saved.dept_id_set == "31,37"
    assert Repo.get_by!(SysRoleMenu, role_id: role.role_id, menu_id: menu.menu_id)
  end

  # 角色目录读取失败时不显示可提交的空权限表单。
  test "deleted role permission reads and writes show failure feedback", %{conn: conn} do
    {actor, _actor_role} = create_actor(["role:read", "role:manage"])
    role = create_role("deleted permission target", "ALL", "", [])
    {:ok, view} = login_with_step_up(conn, actor)
    render_click(view, "show-panel", %{"panel" => "roles"})

    Repo.update!(Ecto.Changeset.change(role, deleted: true))
    render_click(view, "open-role-permissions", %{"role-id" => to_string(role.role_id)})
    assert live_socket(view).assigns.role_permissions_form["loaded"] == false
    assert has_element?(view, "#role-permissions-feedback[role='alert']")
    refute has_element?(view, "#role-permissions-modal form[phx-submit='save-role-permissions']")
  end

  # 目标角色在编辑窗口打开后删除时，保存失败必须留在权限窗口并显示错误码。
  test "permission save failure stays visible after its target disappears", %{conn: conn} do
    {actor, _actor_role} = create_actor(["role:read", "role:manage"])
    role = create_role("permission write failure target", "ALL", "", [])
    {:ok, view} = login_with_step_up(conn, actor)
    render_click(view, "show-panel", %{"panel" => "roles"})
    render_click(view, "open-role-permissions", %{"role-id" => to_string(role.role_id)})

    Repo.update!(Ecto.Changeset.change(role, deleted: true))
    render_submit(view, "save-role-permissions", %{})

    feedback = live_socket(view).assigns.role_permissions_feedback
    assert Feedback.code(feedback) == "resource_not_found"
    assert Feedback.message(feedback) == "记录不存在"
    assert live_socket(view).assigns.active_modal == "role-permissions"
    assert has_element?(view, "#role-permissions-feedback[role='alert']", "记录不存在")
  end

  # 权限绑定变化会让已有会话失效，事件不能沿用旧的角色编辑能力。
  test "role permission changes expire a stale LiveView session", %{conn: conn} do
    {actor, actor_role} = create_actor(["role:read", "role:update"])
    role = create_role("permission change target", "ALL", "", [])
    {:ok, view} = login_with_step_up(conn, actor)
    render_click(view, "show-panel", %{"panel" => "roles"})
    assert has_element?(view, "button[phx-click='edit-role']")

    permission = Repo.get_by!(SysPermission, permission: "role:update")

    Repo.delete!(%SysRolePermission{
      role_id: actor_role.role_id,
      permission_id: permission.permission_id
    })

    PolicyCache.invalidate()

    html = render_click(view, "edit-role", %{"role-id" => to_string(role.role_id)})
    assert html =~ "登录状态已失效"
    assert live_socket(view).assigns.current_user == nil
  end

  # 没有 role:read 的账号不能通过伪造导航事件打开角色面板。
  test "roles panel remains unavailable without role:read", %{conn: conn} do
    {actor, _actor_role} = create_actor(["user:read"])
    {:ok, view} = login(conn, actor)
    current_panel = live_socket(view).assigns.active_panel

    render_click(view, "show-panel", %{"panel" => "roles"})

    assert live_socket(view).assigns.active_panel == current_panel
    refute has_element?(view, ".roles-page")
  end

  # 测试主体使用真实权限目录和真实角色绑定，覆盖服务端授权链。
  defp create_actor(permissions) do
    role = create_role(unique("role_actor"), "ALL", "", permissions)
    {:ok, user} = create_user(role, unique("role_actor_user"))
    {user, role}
  end

  # 直接建立目标角色，避免测试通过管理员身份绕过页面权限检查。
  defp create_role(name, scope, dept_ids, permissions) do
    role =
      %SysRole{role_id: Identity.v7()}
      |> SysRole.changeset(%{
        role_name: name,
        role_key: unique("role_target"),
        role_sort: 1,
        data_scope: scope,
        dept_id_set: dept_ids,
        status: 1
      })
      |> Repo.insert!()

    Enum.each(permissions, fn code ->
      permission = Repo.get_by!(SysPermission, permission: code)

      Repo.insert!(%SysRolePermission{
        role_id: role.role_id,
        permission_id: permission.permission_id
      })
    end)

    role
  end

  # 为元数据保留测试添加真实菜单绑定。
  defp create_menu_for_role(role) do
    menu =
      %SysMenu{menu_id: Identity.v7()}
      |> SysMenu.changeset(%{
        menu_code: unique("role_menu"),
        menu_name: unique("角色菜单"),
        menu_type: 1,
        status: 1
      })
      |> Repo.insert!()

    Repo.insert!(%SysRoleMenu{role_id: role.role_id, menu_id: menu.menu_id})
    menu
  end

  # 测试用户使用常规登录流程，不直接注入 LiveView 权限 assigns。
  defp create_user(role, username) do
    Repo.insert(%SysUser{
      user_id: Identity.v7(),
      role_id: role.role_id,
      username: username,
      password: Bcrypt.hash_pwd_salt("Strong!123"),
      status: 1
    })
  end

  defp login(conn, user) do
    {:ok, view, _html} = live(conn, "/")
    render_submit(view, "login", %{"username" => user.username, "password" => "Strong!123"})
    {:ok, view}
  end

  # 敏感写操作使用真实 TOTP enrollment 和 step-up 会话。
  defp login_with_step_up(conn, user) do
    {:ok, view} = login(conn, user)
    token = live_socket(view).assigns.access_token
    {:ok, claims} = Auth.Token.verify(token, Auth.Token.access_type())

    {:ok, enrollment} =
      Mfa.begin_enrollment(user.user_id, user.username, claims["client_id"], claims["sid"])

    now = System.system_time(:second)

    {:ok, _verification} =
      Mfa.verify_enrollment(
        user.user_id,
        enrollment.challenge_id,
        claims["client_id"],
        claims["sid"],
        Totp.code(enrollment.secret, now),
        nil
      )

    render_click(view, "logout")
    render_submit(view, "login", %{"username" => user.username, "password" => "Strong!123"})
    render_click(view, "begin-liveview-step-up")

    render_submit(view, "verify-liveview-step-up", %{
      "code" => Totp.code(enrollment.secret, now + Totp.step_seconds())
    })

    {:ok, view}
  end

  defp live_socket(view), do: find_socket(:sys.get_state(view.pid))
  defp find_socket(%Phoenix.LiveView.Socket{} = socket), do: socket
  defp find_socket(%{} = map), do: map |> Map.values() |> Enum.find_value(&find_socket/1)

  defp find_socket(tuple) when is_tuple(tuple),
    do: tuple |> Tuple.to_list() |> Enum.find_value(&find_socket/1)

  defp find_socket(list) when is_list(list), do: Enum.find_value(list, &find_socket/1)
  defp find_socket(_value), do: nil
  defp unique(prefix), do: "#{prefix}_#{System.unique_integer([:positive])}"
end
