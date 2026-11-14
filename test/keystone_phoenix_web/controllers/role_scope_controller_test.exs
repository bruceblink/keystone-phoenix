defmodule KeystonePhoenixWeb.RoleScopeControllerTest do
  use KeystonePhoenixWeb.ConnCase, async: false

  alias KeystonePhoenix.Auth
  alias KeystonePhoenix.Authz.{PolicyCache, SysPermission, SysRolePermission}
  alias KeystonePhoenix.Identity
  alias KeystonePhoenix.Repo
  alias KeystonePhoenix.Role.SysRole
  alias KeystonePhoenix.User.SysUser

  @tag :integration
  test "role user batch HTTP commands roll back mixed targets" do
    actor_role = create_role("TENANT")
    grant_permission(actor_role.role_id, "role:update")
    grant_permission(actor_role.role_id, "role:assign")
    target_role = create_role("TENANT")
    actor = create_user(actor_role.role_id)
    target = create_user(nil)
    missing_id = Identity.v7()
    {:ok, tokens} = Auth.login_plaintext(actor.username, "Strong!123")

    assign_path =
      "/api/v1/system/role/#{target_role.role_id}/users/#{target.user_id},#{missing_id}/grant/bulk"

    response = post(authorized(tokens.token), assign_path, %{})
    assert get_in(json_response(response, 404), ["error", "code"]) == "validation_failed"
    assert Repo.get!(SysUser, target.user_id).role_id == nil

    assert %{"success" => true} =
             json_response(
               post(
                 authorized(tokens.token),
                 "/api/v1/system/role/#{target_role.role_id}/users/#{target.user_id}/grant/bulk",
                 %{}
               ),
               200
             )

    assert Repo.get!(SysUser, target.user_id).role_id == target_role.role_id

    unassign_path =
      "/api/v1/system/role/users/#{target.user_id},#{missing_id}/grant/bulk"

    response = delete(authorized(tokens.token), unassign_path, %{})
    assert get_in(json_response(response, 404), ["error", "code"]) == "validation_failed"
    assert Repo.get!(SysUser, target.user_id).role_id == target_role.role_id
  end

  defp authorized(token), do: put_req_header(build_conn(), "authorization", "Bearer #{token}")

  defp create_role(data_scope) do
    %SysRole{}
    |> SysRole.changeset(%{
      role_name: "角色范围 HTTP 测试",
      role_key: "role_scope_http_#{System.unique_integer([:positive])}",
      role_sort: 1,
      data_scope: data_scope,
      status: 1
    })
    |> Repo.insert!()
  end

  defp grant_permission(role_id, permission) do
    permission = Repo.get_by!(SysPermission, permission: permission)
    Repo.insert!(%SysRolePermission{role_id: role_id, permission_id: permission.permission_id})
    PolicyCache.invalidate()
  end

  defp create_user(role_id) do
    %SysUser{}
    |> SysUser.create_changeset(%{
      user_id: Identity.v7(),
      username: "role_scope_http_#{System.unique_integer([:positive])}",
      password: "Strong!123",
      role_id: role_id,
      status: 1
    })
    |> Repo.insert!()
  end
end
