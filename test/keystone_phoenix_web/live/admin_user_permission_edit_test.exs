defmodule KeystonePhoenixWeb.AdminUserPermissionEditTest do
  use KeystonePhoenixWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import KeystonePhoenixWeb.LiveAuthenticationTestSupport

  alias KeystonePhoenix.Authz.{PolicyCache, SysPermission, SysRolePermission}
  alias KeystonePhoenix.Repo
  alias KeystonePhoenix.Role.SysRole
  alias KeystonePhoenix.User.RoleMembership
  alias KeystonePhoenix.User.SysUser
  alias KeystonePhoenixWeb.Live.AdminEvents.Accounts, as: AccountEvents
  alias KeystonePhoenixWeb.Live.AdminPages.Accounts
  alias KeystonePhoenixWeb.Live.AdminSupport

  setup do
    ensure_captcha_config()
    disable_captcha()
    clear_config_cache()
    on_exit(&clear_config_cache/0)

    actor_role = create_role(["user:read", "user:update"])
    {:ok, actor} = create_user(%{"role_id" => actor_role.role_id})
    {target, target_roles} = create_target_user()

    {:ok, actor: actor, target: target, target_roles: target_roles}
  end

  @tag :integration
  test "user update permission shows edit, preserves roles, and saves checkbox state", %{
    conn: conn,
    actor: actor,
    target: target,
    target_roles: target_roles
  } do
    {:ok, view, _html} = login_view(conn, actor)
    render_click(view, "show-panel", %{"panel" => "users"})

    assert has_element?(view, "button[phx-click='edit-user']")
    refute has_element?(view, "button[phx-click='new-user']")
    refute has_element?(view, "button[phx-click='new-user-import']")
    refute has_element?(view, "button[phx-click='delete-users']")

    render_click(view, "edit-user", %{"user-id" => to_string(target.user_id)})
    assert has_element?(view, "form#user-form")
    assert has_element?(view, "input[type='hidden'][name='enabled'][value='false']")
    refute has_element?(view, "input[name='roleCodes[]']")
    assert has_element?(view, "#user-role-preserved")

    # 从渲染后的表单提交，确认已选复选框不会被隐藏 false 值覆盖。
    view
    |> form("#user-form", %{"nickname" => "资料已更新"})
    |> render_submit()

    updated = Repo.get!(SysUser, target.user_id)
    assert updated.nickname == "资料已更新"
    assert updated.status == 1
    assert target_role_ids(target) == target_roles

    render_click(view, "edit-user", %{"user-id" => to_string(target.user_id)})

    render_submit(view, "save-user", %{
      "userId" => to_string(target.user_id),
      "username" => target.username,
      "nickname" => "已停用",
      "enabled" => "false"
    })

    assert Repo.get!(SysUser, target.user_id).status == 0
    assert target_role_ids(target) == target_roles
  end

  @tag :integration
  test "a forged role change is rejected without role assignment permission", %{
    conn: conn,
    actor: actor,
    target: target,
    target_roles: target_roles
  } do
    {:ok, view, _html} = login_view(conn, actor)
    render_click(view, "show-panel", %{"panel" => "users"})
    render_click(view, "edit-user", %{"user-id" => to_string(target.user_id)})

    render_submit(view, "save-user", %{
      "userId" => to_string(target.user_id),
      "username" => target.username,
      "nickname" => "不应保存",
      "roleCodes" => [unique("forged_role")]
    })

    assert Repo.get!(SysUser, target.user_id).nickname == target.nickname
    assert target_role_ids(target) == target_roles
    assert match?({:error, _, _}, live_socket(view).assigns.user_feedback)
  end

  @tag :integration
  test "create permission without role assignment creates an unassigned account", %{conn: conn} do
    role = create_role(["user:read", "user:create"])
    {:ok, creator} = create_user(%{"role_id" => role.role_id})
    {:ok, view, _html} = login_view(conn, creator)
    render_click(view, "show-panel", %{"panel" => "users"})
    render_click(view, "new-user")

    assert has_element?(view, "#user-role-preserved", "新用户将以未分配角色状态创建")
    refute has_element?(view, "input[name='roleCodes[]']")

    username = unique("unassigned_live_user")

    render_submit(view, "save-user", %{
      "userId" => "",
      "username" => username,
      "nickname" => "未分配角色用户",
      "password" => "Created!123",
      "enabled" => "true"
    })

    created = Repo.get_by!(SysUser, username: username)
    assert created.role_id == nil
    assert RoleMembership.list_role_ids_for_user(created.user_id) == []
  end

  @tag :integration
  test "role permissions without role data scope create an unassigned account", %{conn: conn} do
    {actor_dept, _target_dept} = insert_test_departments()
    role = create_role(["user:read", "user:create", "role:read", "role:assign"], "DEPARTMENT")

    {:ok, creator} =
      create_user(%{"role_id" => role.role_id, "dept_id" => actor_dept.dept_id})

    {:ok, view, _html} = login_view(conn, creator)
    render_click(view, "show-panel", %{"panel" => "users"})
    render_click(view, "new-user")

    assert live_socket(view).assigns.role_scope_allowed == false
    assert has_element?(view, "#user-role-preserved", "当前账号没有角色数据范围")
    assert has_element?(view, "#user-role-preserved", "新用户将以未分配角色状态创建")
    refute has_element?(view, "input[name='roleCodes[]']")

    username = unique("out_of_scope_unassigned_user")

    render_submit(view, "save-user", %{
      "userId" => "",
      "username" => username,
      "nickname" => "无角色范围创建",
      "password" => "Created!123",
      "deptId" => to_string(actor_dept.dept_id),
      "enabled" => "true"
    })

    created = Repo.get_by!(SysUser, username: username)
    assert is_nil(created.role_id)
    assert RoleMembership.list_role_ids_for_user(created.user_id) == []
  end

  @tag :integration
  test "a failed role-directory query hides role fields and reports preservation", %{
    conn: conn,
    target: target,
    target_roles: target_roles
  } do
    permissions = ["user:read", "user:create", "user:update", "role:read", "role:assign"]
    role = create_role(permissions)
    {:ok, reader} = create_user(%{"role_id" => role.role_id})
    {:ok, view, _html} = login_view(conn, reader)
    socket = live_socket(view)
    unavailable_table = "sys_role_permission_read_failure"

    Repo.query!("ALTER TABLE sys_role_permission RENAME TO #{unavailable_table}")

    role_directory_feedback =
      try do
        dashboard =
          AdminSupport.load_dashboard_for_permissions(socket.assigns.current_user, permissions)

        assert dashboard.role_rows == []
        assert dashboard.role_scope_allowed
        assert dashboard.role_directory_feedback

        target_row =
          Enum.find(
            socket.assigns.user_rows,
            &(to_string(&1["userId"]) == to_string(target.user_id))
          )

        html =
          render_component(&Accounts.users/1, %{
            active_modal: "user",
            user_rows: [target_row],
            user_total: 0,
            users_server_paged: false,
            user_form: %{"userId" => to_string(target.user_id), "username" => target.username},
            user_feedback: nil,
            user_query: "",
            user_display_name_query: "",
            selected_user_ids: [],
            user_import_result: nil,
            user_import_upload: nil,
            dept_rows: [],
            post_rows: [],
            role_rows: dashboard.role_rows,
            role_directory_feedback: dashboard.role_directory_feedback,
            role_scope_allowed: true,
            page_num: 1,
            page_size: 20,
            permissions: permissions
          })

        refute html =~ ~s(name="roleCodes[]")
        assert html =~ "角色目录读取失败"
        assert html =~ "保存资料时会保留原角色"

        create_html =
          render_component(&Accounts.users/1, %{
            active_modal: "user",
            user_rows: [],
            user_total: 0,
            users_server_paged: false,
            user_form: %{"userId" => "", "username" => "", "enabled" => true},
            user_feedback: nil,
            user_query: "",
            user_display_name_query: "",
            selected_user_ids: [],
            user_import_result: nil,
            user_import_upload: nil,
            dept_rows: [],
            post_rows: [],
            role_rows: dashboard.role_rows,
            role_directory_feedback: dashboard.role_directory_feedback,
            role_scope_allowed: true,
            page_num: 1,
            page_size: 1,
            permissions: permissions
          })

        assert create_html =~ "暂不能创建用户"
        assert create_html =~ ~s(type="submit" disabled)

        dashboard.role_directory_feedback
      after
        Repo.query!("ALTER TABLE #{unavailable_table} RENAME TO sys_role_permission")
      end

    failed_directory_socket = %{
      socket
      | assigns:
          socket.assigns
          |> Map.put(:role_rows, [])
          |> Map.put(:role_directory_feedback, role_directory_feedback)
    }

    assert {:noreply, saved_socket} =
             AccountEvents.handle_event(
               "save-user",
               %{
                 "userId" => to_string(target.user_id),
                 "username" => target.username,
                 "nickname" => "目录故障时仅更新资料",
                 "enabled" => "true"
               },
               failed_directory_socket
             )

    assert Repo.get!(SysUser, target.user_id).nickname == "目录故障时仅更新资料"
    assert target_role_ids(target) == target_roles
    assert saved_socket.assigns.role_directory_feedback == role_directory_feedback

    {:noreply, new_form_socket} = AccountEvents.handle_event("new-user", %{}, saved_socket)
    username = unique("blocked_directory_user")

    assert {:noreply, blocked_socket} =
             AccountEvents.handle_event(
               "save-user",
               %{
                 "userId" => "",
                 "username" => username,
                 "nickname" => "目录不可用时不得创建",
                 "password" => "Created!123"
               },
               new_form_socket
             )

    assert KeystonePhoenixWeb.Live.AdminPages.Feedback.code(blocked_socket.assigns.user_feedback) ==
             "service_unavailable"

    assert Repo.get_by(SysUser, username: username) == nil
  end

  test "enabled normalization accepts checked and unchecked hidden values" do
    assert {:ok, %{"status" => 1}} =
             KeystonePhoenixWeb.Live.AdminEventsAccountsParams.normalize_user_params(%{
               "enabled" => ["false", "true"]
             })

    assert {:ok, %{"status" => 0}} =
             KeystonePhoenixWeb.Live.AdminEventsAccountsParams.normalize_user_params(%{
               "enabled" => "false"
             })
  end

  test "user rows keep the actions column when editing is not allowed" do
    html =
      render_component(&Accounts.users/1, %{
        active_modal: nil,
        user_rows: [%{"userId" => Ecto.UUID.generate(), "username" => "reader", "status" => 1}],
        user_total: 1,
        users_server_paged: true,
        user_form: %{"userId" => ""},
        user_feedback: nil,
        user_query: "",
        user_display_name_query: "",
        selected_user_ids: [],
        user_import_result: nil,
        user_import_upload: nil,
        dept_rows: [],
        post_rows: [],
        role_rows: [],
        page_num: 1,
        page_size: 20,
        permissions: ["user:read"]
      })

    assert html =~ "<th scope=\"col\">操作</th>"
    assert Regex.match?(~r/<td class="table-actions">\s*<\/td>/, html)
    refute html =~ ~s(phx-click="edit-user")
  end

  defp create_role(permissions, data_scope \\ "ALL") do
    role =
      %SysRole{}
      |> SysRole.changeset(%{
        role_name: unique("user_edit_role"),
        role_key: unique("user_edit_role_key"),
        role_sort: 1,
        data_scope: data_scope,
        dept_id_set: "",
        status: 1
      })
      |> Repo.insert!()

    Enum.each(permissions, fn permission ->
      entry = Repo.get_by!(SysPermission, permission: permission)

      Repo.insert!(%SysRolePermission{
        role_id: role.role_id,
        permission_id: entry.permission_id
      })
    end)

    PolicyCache.invalidate()
    role
  end

  defp create_target_user do
    first = create_role([])
    second = create_role([])
    {:ok, target} = create_user(%{"role_id" => first.role_id, "nickname" => "原昵称"})
    RoleMembership.replace_user_roles([target.user_id], [first.role_id, second.role_id])
    {target, target_role_ids(target)}
  end

  defp target_role_ids(user) do
    user.user_id
    |> RoleMembership.list_role_ids_for_user()
    |> Enum.sort()
  end
end
