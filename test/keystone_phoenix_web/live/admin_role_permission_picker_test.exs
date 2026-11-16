defmodule KeystonePhoenixWeb.AdminRolePermissionPickerTest do
  use KeystonePhoenixWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias KeystonePhoenix.{Identity, Repo}
  alias KeystonePhoenix.Authz.{SysPermission, SysRolePermission}
  alias KeystonePhoenix.Role.SysRole
  alias KeystonePhoenix.User.SysUser

  setup do
    role_id = Identity.v7()

    _admin_role =
      %SysRole{role_id: role_id}
      |> SysRole.changeset(%{
        role_name: unique("权限选择管理员"),
        role_key: unique("permission_picker_admin"),
        role_sort: 1,
        data_scope: "ALL",
        dept_id_set: "",
        status: 1
      })
      |> Repo.insert!()

    for permission <- Repo.all(SysPermission) do
      Repo.insert!(%SysRolePermission{role_id: role_id, permission_id: permission.permission_id})
    end

    admin =
      Repo.insert!(%SysUser{
        user_id: Identity.v7(),
        role_id: role_id,
        username: unique("permission_picker_admin"),
        password: Bcrypt.hash_pwd_salt("Strong!123"),
        status: 1
      })

    {:ok, admin: admin}
  end

  test "role form selects permissions from the dynamic catalog", %{conn: conn, admin: admin} do
    {:ok, view, _html} = live(conn, "/")
    render_submit(view, "login", %{"username" => admin.username, "password" => "Strong!123"})
    render_click(view, "show-panel", %{"panel" => "roles"})
    render_click(view, "new-role")

    assert has_element?(view, "#role-permission-query")
    assert has_element?(view, "input[phx-value-permission='user:read']")

    render_change(view, "filter-role-permissions", %{"permissionQuery" => "user:read"})
    assert live_socket(view).assigns.role_permission_query == "user:read"

    render_click(view, "toggle-role-permission", %{
      "permission" => "user:read",
      "selected" => "true"
    })

    assert live_socket(view).assigns.role_form["permissions"] == "user:read"

    assert has_element?(view, "input#role-permissions[value='user:read']")
  end

  defp unique(prefix), do: "#{prefix}_#{System.unique_integer([:positive])}"
  defp live_socket(view), do: find_socket(:sys.get_state(view.pid))
  defp find_socket(%Phoenix.LiveView.Socket{} = socket), do: socket
  defp find_socket(%{} = map), do: map |> Map.values() |> Enum.find_value(&find_socket/1)

  defp find_socket(tuple) when is_tuple(tuple),
    do: tuple |> Tuple.to_list() |> Enum.find_value(&find_socket/1)

  defp find_socket(list) when is_list(list), do: Enum.find_value(list, &find_socket/1)
  defp find_socket(_value), do: nil
end
