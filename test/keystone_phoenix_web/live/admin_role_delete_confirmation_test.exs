defmodule KeystonePhoenixWeb.AdminRoleDeleteConfirmationTest do
  @moduledoc "使用真实账号和数据库验收角色批量删除确认流程。"

  use KeystonePhoenixWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias KeystonePhoenix.{Auth, Cache, Identity, Repo, Role}
  alias KeystonePhoenix.Auth.Mfa
  alias KeystonePhoenix.Auth.Mfa.Totp
  alias KeystonePhoenix.Authz.{SysPermission, SysRolePermission}
  alias KeystonePhoenix.Role.SysRole
  alias KeystonePhoenix.User.SysUser

  setup do
    clear_config_cache()
    on_exit(&clear_config_cache/0)

    admin_role =
      %SysRole{role_id: Identity.v7()}
      |> SysRole.changeset(%{
        role_name: unique("角色删除测试管理员"),
        role_key: unique("role_delete_admin"),
        role_sort: 1,
        data_scope: "ALL",
        dept_id_set: "",
        status: 1
      })
      |> Repo.insert!()

    for permission <- Repo.all(SysPermission) do
      Repo.insert!(%SysRolePermission{
        role_id: admin_role.role_id,
        permission_id: permission.permission_id
      })
    end

    admin =
      Repo.insert!(%SysUser{
        user_id: Identity.v7(),
        role_id: admin_role.role_id,
        username: unique("role_delete_admin"),
        password: Bcrypt.hash_pwd_salt("Strong!123"),
        status: 1
      })

    {:ok, admin: admin}
  end

  test "cancel closes the confirmation without deleting or unselecting roles", ctx do
    role = create_role(ctx.admin, "取消后保留的角色")
    {:ok, view} = login(ctx.conn, ctx.admin)

    open_role_delete_confirmation(view, role)
    assert has_element?(view, "#role-delete-modal")

    render_click(view, "close-modal")

    refute has_element?(view, "#role-delete-modal")
    assert live_socket(view).assigns.active_modal == nil
    assert live_socket(view).assigns.selected_role_ids == [to_string(role.role_id)]
    assert Repo.get!(SysRole, role.role_id).deleted == false
  end

  test "an AAL1 confirmation requires step-up and does not delete the selected role", ctx do
    role = create_role(ctx.admin, "需要二次认证的角色")
    {:ok, view, _secret, _enrollment_time} = login_with_enrolled_mfa(ctx.conn, ctx.admin)

    assert {:ok, %{authentication_level: "AAL1"}} =
             Auth.session_context(live_socket(view).assigns.access_token)

    # 此用例验证策略开启后的 step-up；直接设置策略值以保留当前 AAL1 测试会话。
    Repo.update!(Ecto.Changeset.change(Repo.get!(SysUser, ctx.admin.user_id), mfa_required: true))

    open_role_delete_confirmation(view, role)
    render_submit(view, "delete-role", %{"role-ids" => [to_string(role.role_id)]})

    assert has_element?(view, "#mfa-step-up-panel")
    refute has_element?(view, "#role-delete-modal")
    assert render(view) =~ "此操作需要完成二次认证"
    assert live_socket(view).assigns.mfa_step_up_required
    assert live_socket(view).assigns.selected_role_ids == [to_string(role.role_id)]
    assert Repo.get!(SysRole, role.role_id).deleted == false
  end

  test "an AAL2 confirmation deletes only the selected roles", ctx do
    selected_roles = [
      create_role(ctx.admin, "确认删除的角色一"),
      create_role(ctx.admin, "确认删除的角色二")
    ]

    retained_role = create_role(ctx.admin, "未选择保留的角色")
    {:ok, view} = login_with_step_up(ctx.conn, ctx.admin)

    assert {:ok, %{authentication_level: "AAL2"}} =
             Auth.session_context(live_socket(view).assigns.access_token)

    open_role_delete_confirmation(view, selected_roles)

    render_submit(view, "delete-role", %{
      "role-ids" => Enum.map(selected_roles, &to_string(&1.role_id))
    })

    assert render(view) =~ "已删除 2 个角色"
    assert live_socket(view).assigns.active_modal == nil
    assert live_socket(view).assigns.selected_role_ids == []

    for role <- selected_roles do
      assert Repo.get!(SysRole, role.role_id).deleted
    end

    refute Repo.get!(SysRole, retained_role.role_id).deleted
  end

  test "a failed deletion keeps the confirmation open and displays the error", ctx do
    role = create_role(ctx.admin, "仍有关联用户的角色")

    Repo.insert!(%SysUser{
      user_id: Identity.v7(),
      role_id: role.role_id,
      username: unique("role_delete_member"),
      password: Bcrypt.hash_pwd_salt("Strong!123"),
      status: 1
    })

    {:ok, view} = login_with_step_up(ctx.conn, ctx.admin)
    open_role_delete_confirmation(view, role)
    render_submit(view, "delete-role", %{"role-ids" => [to_string(role.role_id)]})

    assert has_element?(view, "#role-delete-modal [role='alert']", "角色存在用户，不能删除")
    assert has_element?(view, "#role-delete-error-code", "错误码：role_has_members")
    refute has_element?(view, "#role-feedback")
    assert live_socket(view).assigns.active_modal == "role-delete"
    assert live_socket(view).assigns.selected_role_ids == [to_string(role.role_id)]
    refute Repo.get!(SysRole, role.role_id).deleted

    render_click(view, "close-modal")

    refute has_element?(view, "#role-delete-modal")
    refute has_element?(view, "#role-feedback")
    assert live_socket(view).assigns.role_feedback == nil
  end

  # 创建角色时使用具备真实角色权限的测试账号，走 Role 服务和数据库。
  defp create_role(admin, name) do
    {:ok, role} =
      Role.create_role(
        %{
          "roleName" => unique(name),
          "roleKey" => unique("role_delete_target"),
          "roleSort" => 7,
          "dataScope" => "ALL",
          "status" => 1,
          "menuIds" => []
        },
        authorization: %{principal: admin, permission: "role:create"}
      )

    role
  end

  # 通过真实角色列表选择角色，再打开页面提供的批量删除确认框。
  defp open_role_delete_confirmation(view, roles) do
    roles = List.wrap(roles)
    role_ids = Enum.map(roles, &to_string(&1.role_id))
    render_click(view, "show-panel", %{"panel" => "roles"})

    for role_id <- role_ids do
      render_click(view, "toggle-role-selection", %{"role-id" => role_id, "selected" => "true"})
    end

    assert MapSet.new(live_socket(view).assigns.selected_role_ids) == MapSet.new(role_ids)
    render_click(view, "open-role-delete")
    assert live_socket(view).assigns.active_modal == "role-delete"
    assert has_element?(view, "#role-delete-modal strong", "将删除 #{length(role_ids)} 条角色记录")
    assert has_element?(view, "#role-delete-modal button[form='role-delete-form'][type='submit']")
  end

  # 注册 TOTP 后重新登录，返回持有已登记因子但仍处于 AAL1 的 LiveView。
  defp login_with_enrolled_mfa(conn, user) do
    {:ok, view} = login(conn, user)

    {:ok, claims} =
      Auth.Token.verify(live_socket(view).assigns.access_token, Auth.Token.access_type())

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
    {:ok, view, enrollment.secret, now}
  end

  # 在 AAL1 会话登记 TOTP，再通过 LiveView 完成 step-up 取得 AAL2 令牌。
  defp login_with_step_up(conn, user) do
    {:ok, view, secret, enrollment_time} = login_with_enrolled_mfa(conn, user)

    render_click(view, "begin-liveview-step-up")

    render_submit(view, "verify-liveview-step-up", %{
      "code" => Totp.code(secret, enrollment_time + Totp.step_seconds())
    })

    refute live_socket(view).assigns.mfa_step_up_required
    {:ok, view}
  end

  defp login(conn, user) do
    {:ok, view, _html} = live(conn, "/")
    render_submit(view, "login", %{"username" => user.username, "password" => "Strong!123"})
    assert has_element?(view, "nav[aria-label='主导航']")
    {:ok, view}
  end

  defp clear_config_cache, do: Cache.delete_prefix("keystone:system:config:")

  defp live_socket(view), do: find_socket(:sys.get_state(view.pid))
  defp find_socket(%Phoenix.LiveView.Socket{} = socket), do: socket
  defp find_socket(%{} = map), do: map |> Map.values() |> Enum.find_value(&find_socket/1)

  defp find_socket(tuple) when is_tuple(tuple),
    do: tuple |> Tuple.to_list() |> Enum.find_value(&find_socket/1)

  defp find_socket(list) when is_list(list), do: Enum.find_value(list, &find_socket/1)
  defp find_socket(_value), do: nil

  defp unique(prefix), do: "#{prefix}_#{System.unique_integer([:positive])}"
end
