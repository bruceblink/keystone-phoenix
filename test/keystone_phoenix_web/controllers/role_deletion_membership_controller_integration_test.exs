defmodule KeystonePhoenixWeb.RoleDeletionMembershipControllerIntegrationTest do
  use KeystonePhoenixWeb.ConnCase, async: false

  @moduletag :integration

  alias KeystonePhoenix.Authz.{PolicyCache, SysPermission, SysRolePermission}
  alias KeystonePhoenix.Identity
  alias KeystonePhoenix.Repo
  alias KeystonePhoenix.Role.SysRole
  alias KeystonePhoenix.User.SysUser
  alias KeystonePhoenix.User.SysUserRole

  # 使用真实 Bearer 请求验证次要成员冲突响应和整批数据库回滚。
  test "mixed role batch delete rejects a secondary member without deleting the empty role" do
    actor_role = create_role("ALL")
    grant_permission(actor_role.role_id, "role:delete")
    empty_role = create_role("ALL")
    primary_role = create_role("ALL")
    secondary_role = create_role("ALL")
    actor = create_user(actor_role.role_id)
    member = create_user(primary_role.role_id)
    Repo.insert!(%SysUserRole{user_id: member.user_id, role_id: secondary_role.role_id})
    token = step_up_token(actor)

    response =
      delete(
        authorized(token),
        "/api/v1/roles",
        %{"ids" => Enum.join([empty_role.role_id, secondary_role.role_id], ",")}
      )

    assert get_in(json_response(response, 422), ["error", "code"]) == "role_has_members"
    refute Repo.get!(SysRole, empty_role.role_id).deleted
    refute Repo.get!(SysRole, secondary_role.role_id).deleted
  end

  test "protected administrator role returns a distinct 422 error code" do
    actor_role = create_role("ALL")
    grant_permission(actor_role.role_id, "role:delete")
    actor = create_user(actor_role.role_id)
    protected_role = Repo.get_by!(SysRole, role_key: "admin", deleted: false)
    token = step_up_token(actor)

    response = delete(authorized(token), "/api/v1/roles/#{protected_role.role_id}")

    assert get_in(json_response(response, 422), ["error", "code"]) == "role_protected"
    refute Repo.get!(SysRole, protected_role.role_id).deleted
  end

  defp authorized(token), do: put_req_header(build_conn(), "authorization", "Bearer #{token}")

  defp create_role(data_scope) do
    %SysRole{}
    |> SysRole.changeset(%{
      role_name: "角色删除 HTTP 测试",
      role_key: "role_delete_http_#{System.unique_integer([:positive])}",
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
    user =
      %SysUser{}
      |> SysUser.create_changeset(%{
        user_id: Identity.v7(),
        username: "role_delete_http_#{System.unique_integer([:positive])}",
        password: "Strong!123",
        role_id: role_id,
        status: 1
      })
      |> Repo.insert!()

    Repo.insert!(%SysUserRole{user_id: user.user_id, role_id: role_id})
    user
  end
end
