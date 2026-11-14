defmodule KeystonePhoenixWeb.ResourceScopeControllerTest do
  use KeystonePhoenixWeb.ConnCase, async: false

  alias KeystonePhoenix.Auth
  alias KeystonePhoenix.Authz.{PolicyCache, SysPermission, SysRolePermission}
  alias KeystonePhoenix.Identity
  alias KeystonePhoenix.Repo
  alias KeystonePhoenix.Role.SysRole
  alias KeystonePhoenix.User.SysUser

  @tag :integration
  test "global resource entries require ALL or TENANT", %{conn: conn} do
    role = insert_role("DEPARTMENT")
    link_permission(role.role_id, "role:read")
    user = insert_user(role.role_id)
    {:ok, tokens} = Auth.login_plaintext(user.username, "Strong!123")

    response = get(authorized(conn, tokens.token), "/api/v1/system/role/list")

    assert get_in(json_response(response, 403), ["error", "code"]) == "data_scope_denied"

    Repo.update!(Ecto.Changeset.change(role, data_scope: "TENANT"))
    {:ok, refreshed} = Auth.login_plaintext(user.username, "Strong!123", true)

    response = get(authorized(build_conn(), refreshed.token), "/api/v1/system/role/list")
    assert response.status == 200
    assert json_response(response, 200)["success"] == true
  end

  defp authorized(conn, token), do: put_req_header(conn, "authorization", "Bearer #{token}")

  defp insert_role(data_scope) do
    %SysRole{}
    |> SysRole.changeset(%{
      role_name: "资源范围测试",
      role_key: "resource_scope_#{System.unique_integer([:positive])}",
      role_sort: 1,
      data_scope: data_scope,
      status: 1
    })
    |> Repo.insert!()
  end

  defp link_permission(role_id, permission) do
    entry = Repo.get_by!(SysPermission, permission: permission)

    Repo.insert!(%SysRolePermission{role_id: role_id, permission_id: entry.permission_id})
    PolicyCache.invalidate()
  end

  defp insert_user(role_id) do
    %SysUser{}
    |> SysUser.create_changeset(%{
      user_id: Identity.v7(),
      role_id: role_id,
      username: "resource_scope_#{System.unique_integer([:positive])}",
      password: "Strong!123",
      status: 1
    })
    |> Repo.insert!()
  end
end
