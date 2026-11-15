defmodule KeystonePhoenixWeb.MenuManagementControllerTest do
  use KeystonePhoenixWeb.ConnCase, async: false

  alias KeystonePhoenix.Auth
  alias KeystonePhoenix.Authz.{PolicyCache, SysPermission, SysRolePermission}
  alias KeystonePhoenix.Identity
  alias KeystonePhoenix.Menu.SysMenu
  alias KeystonePhoenix.Repo
  alias KeystonePhoenix.Role.SysRoleMenu
  alias KeystonePhoenix.Role.SysRole
  alias KeystonePhoenix.User.SysUser

  @tag :integration
  test "menu:manage reads the full menu tree and current role bindings" do
    role = insert_role(["menu:manage"])
    user = insert_user(role.role_id)
    root = insert_menu("manage_root", 0)
    child = insert_menu("manage_child", 0, root.menu_id)
    token = login(user)

    response = get(authorized(build_conn(), token), "/api/v1/menus")
    assert %{"success" => true, "data" => rows} = json_response(response, 200)
    root_row = Enum.find(rows, &(&1["id"] == root.menu_id))
    assert root_row["enabled"] == false
    assert Enum.any?(root_row["children"], &(&1["id"] == child.menu_id))

    assert %{"success" => true, "data" => %{"roleCodes" => []}} =
             json_response(
               get(authorized(build_conn(), token), "/api/v1/menus/#{root.menu_id}/roles"),
               200
             )

    assert %{"success" => true, "data" => %{"updated" => true}} =
             json_response(
               put(authorized(build_conn(), token), "/api/v1/menus/#{root.menu_id}/roles", %{
                 "roleCodes" => [role.role_key]
               }),
               200
             )

    assert %{"success" => true, "data" => %{"roleCodes" => [role_code]}} =
             json_response(
               get(authorized(build_conn(), token), "/api/v1/menus/#{root.menu_id}/roles"),
               200
             )

    assert role_code == role.role_key

    assert json_response(
             get(authorized(build_conn(), token), "/api/v1/menus/#{Identity.v7()}/roles"),
             404
           )["success"] == false
  end

  @tag :integration
  test "menu:read and dropdown only expose enabled assigned menus" do
    role = insert_role(["menu:read"])
    user = insert_user(role.role_id)
    enabled = insert_menu("reader_enabled", 1)
    disabled = insert_menu("reader_disabled", 0)
    unassigned = insert_menu("reader_unassigned", 1)
    assign_menu(role.role_id, enabled.menu_id)
    assign_menu(role.role_id, disabled.menu_id)
    token = login(user)

    rows = json_response(get(authorized(build_conn(), token), "/api/v1/menus"), 200)["data"]
    assert Enum.any?(rows, &(&1["id"] == enabled.menu_id))
    refute Enum.any?(rows, &(&1["id"] == disabled.menu_id))
    refute Enum.any?(rows, &(&1["id"] == unassigned.menu_id))

    dropdown =
      json_response(get(authorized(build_conn(), token), "/api/v1/menus/dropdown"), 200)["data"]

    assert Enum.any?(dropdown, &(&1["id"] == enabled.menu_id))
    refute Enum.any?(dropdown, &(&1["id"] == disabled.menu_id))
    refute Enum.any?(dropdown, &(&1["id"] == unassigned.menu_id))
  end

  defp insert_role(permissions) do
    role =
      %SysRole{}
      |> SysRole.changeset(%{
        role_name: unique("菜单角色"),
        role_key: unique("menu_role"),
        role_sort: 1,
        data_scope: "ALL",
        status: 1
      })
      |> Repo.insert!()

    Enum.each(permissions, fn permission ->
      permission_id = Repo.get_by!(SysPermission, permission: permission).permission_id
      Repo.insert!(%SysRolePermission{role_id: role.role_id, permission_id: permission_id})
    end)

    PolicyCache.invalidate()
    role
  end

  defp insert_user(role_id) do
    %SysUser{user_id: Identity.v7()}
    |> SysUser.create_changeset(%{
      username: unique("menu_user"),
      password: "Strong!123",
      nickname: "菜单测试用户",
      role_id: role_id,
      status: 1
    })
    |> Repo.insert!()
  end

  defp insert_menu(code, status, parent_id \\ nil) do
    %SysMenu{}
    |> SysMenu.changeset(%{
      menu_code: "#{code}_#{System.unique_integer([:positive])}",
      menu_name: code,
      menu_type: 1,
      menu_sort: 1,
      parent_id: parent_id,
      status: status
    })
    |> Repo.insert!()
  end

  defp assign_menu(role_id, menu_id),
    do: Repo.insert!(%SysRoleMenu{role_id: role_id, menu_id: menu_id})

  defp login(user) do
    {:ok, tokens} = Auth.login_plaintext(user.username, "Strong!123")
    tokens.token
  end

  defp authorized(conn, token),
    do: Plug.Conn.put_req_header(conn, "authorization", "Bearer #{token}")

  defp unique(prefix), do: "#{prefix}_#{System.unique_integer([:positive])}"
end
