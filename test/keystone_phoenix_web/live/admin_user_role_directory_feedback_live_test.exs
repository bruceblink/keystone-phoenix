defmodule KeystonePhoenixWeb.AdminUserRoleDirectoryFeedbackLiveTest do
  @moduledoc "验证用户编辑页在角色目录读取失败时保留失败反馈。"

  use KeystonePhoenixWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import KeystonePhoenixWeb.LiveAuthenticationTestSupport

  alias KeystonePhoenix.Authz.{PolicyCache, SysPermission, SysRolePermission}
  alias KeystonePhoenix.Repo
  alias KeystonePhoenix.Role.SysRole
  alias KeystonePhoenix.User.SysUser
  alias KeystonePhoenixWeb.Live.AdminSupport

  setup do
    ensure_captcha_config()
    disable_captcha()
    clear_config_cache()
    on_exit(&clear_config_cache/0)
    :ok
  end

  @tag :integration
  test "the user modal displays role-directory failure and blocks creation", %{conn: conn} do
    role = create_role(["user:read", "user:create", "role:read", "role:assign"])
    {:ok, actor} = create_user(%{"role_id" => role.role_id})
    {:ok, view, _html} = login_view(conn, actor)
    socket = live_socket(view)
    unavailable_table = "sys_role_permission_read_failure"

    Repo.query!("ALTER TABLE sys_role_permission RENAME TO #{unavailable_table}")

    role_directory_feedback =
      try do
        dashboard =
          AdminSupport.load_dashboard_for_permissions(
            socket.assigns.current_user,
            socket.assigns.permissions
          )

        assert dashboard.role_scope_allowed
        assert dashboard.role_directory_feedback
        dashboard.role_directory_feedback
      after
        Repo.query!("ALTER TABLE #{unavailable_table} RENAME TO sys_role_permission")
      end

    # 注入由真实目录查询故障生成的反馈，再从实际 LiveView 页面打开用户表单。
    :sys.replace_state(
      view.pid,
      &put_socket_assign(&1, :role_directory_feedback, role_directory_feedback)
    )

    render_click(view, "show-panel", %{"panel" => "users"})
    render_click(view, "new-user")

    assert has_element?(view, "#user-role-feedback", "角色目录读取失败")
    assert has_element?(view, "#user-role-feedback", "暂不能创建用户")
    assert has_element?(view, "form#user-form button[type='submit'][disabled]")

    username = unique("role_directory_unavailable_user")

    render_submit(view, "save-user", %{
      "userId" => "",
      "username" => username,
      "nickname" => "目录不可用时不得创建",
      "password" => "Created!123",
      "enabled" => "true"
    })

    assert Repo.get_by(SysUser, username: username) == nil
  end

  defp put_socket_assign(%Phoenix.LiveView.Socket{} = socket, key, value),
    do: %{socket | assigns: Map.put(socket.assigns, key, value)}

  defp put_socket_assign(map, key, value) when is_map(map) do
    Enum.reduce(map, map, fn {field, item}, state ->
      Map.put(state, field, put_socket_assign(item, key, value))
    end)
  end

  defp put_socket_assign(tuple, key, value) when is_tuple(tuple) do
    tuple |> Tuple.to_list() |> Enum.map(&put_socket_assign(&1, key, value)) |> List.to_tuple()
  end

  defp put_socket_assign(list, key, value) when is_list(list),
    do: Enum.map(list, &put_socket_assign(&1, key, value))

  defp put_socket_assign(item, _key, _value), do: item

  defp create_role(permissions) do
    role =
      %SysRole{}
      |> SysRole.changeset(%{
        role_name: unique("role_directory_actor"),
        role_key: unique("role_directory_actor_key"),
        role_sort: 1,
        data_scope: "ALL",
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
end
