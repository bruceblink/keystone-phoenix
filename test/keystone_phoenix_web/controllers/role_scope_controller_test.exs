defmodule KeystonePhoenixWeb.RoleScopeControllerTest do
  use KeystonePhoenixWeb.ConnCase, async: false

  import Ecto.Query

  alias KeystonePhoenix.Auth
  alias KeystonePhoenix.Authz.{PolicyCache, SysPermission, SysRolePermission}
  alias KeystonePhoenix.Identity
  alias KeystonePhoenix.Repo
  alias KeystonePhoenix.Role.SysRole
  alias KeystonePhoenix.User.SysUser

  @tag :integration
  test "role permission HTTP replacement updates normalized authorization bindings" do
    actor_role = create_role("TENANT")
    grant_permission(actor_role.role_id, "role:manage")
    target_role = create_role("TENANT")
    actor = create_user(actor_role.role_id)
    {:ok, tokens} = Auth.login_plaintext(actor.username, "Strong!123")

    response =
      put(
        authorized(tokens.token),
        "/api/v1/roles/#{target_role.role_id}/permissions",
        %{"permissions" => ["user:read", "role:read"]}
      )

    assert %{"success" => true, "data" => %{"updated" => true}} = json_response(response, 200)

    assert Repo.all(
             from(binding in SysRolePermission,
               join: permission in SysPermission,
               on: permission.permission_id == binding.permission_id,
               where: binding.role_id == ^target_role.role_id,
               select: permission.permission,
               order_by: permission.permission
             )
           ) == ["role:read", "user:read"]
  end

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

    assign_path = "/api/v1/roles/#{target_role.role_id}/users"

    response =
      put(authorized(tokens.token), assign_path, %{"userIds" => [target.user_id, missing_id]})

    assert get_in(json_response(response, 404), ["error", "code"]) == "validation_failed"
    assert Repo.get!(SysUser, target.user_id).role_id == nil

    assert %{"success" => true} =
             json_response(
               put(
                 authorized(tokens.token),
                 assign_path,
                 %{"userIds" => [target.user_id]}
               ),
               200
             )

    assert Repo.get!(SysUser, target.user_id).role_id == target_role.role_id

    unassign_path = "/api/v1/roles/#{target_role.role_id}/users"

    response =
      delete(authorized(tokens.token), unassign_path, %{"userIds" => [target.user_id, missing_id]})

    assert get_in(json_response(response, 404), ["error", "code"]) == "validation_failed"
    assert Repo.get!(SysUser, target.user_id).role_id == target_role.role_id
  end

  @tag :integration
  test "role member HTTP queries return allocated and unallocated users" do
    actor_role = create_role("TENANT")
    grant_permission(actor_role.role_id, "role:read")
    target_role = create_role("TENANT")
    actor = create_user(actor_role.role_id)
    allocated = create_user(target_role.role_id)
    unallocated = create_user(nil)
    allocated_id = allocated.user_id
    unallocated_id = unallocated.user_id
    {:ok, tokens} = Auth.login_plaintext(actor.username, "Strong!123")

    # 查询接口必须通过真实路由返回 UUID 用户记录，并保持筛选条件生效。
    allocated_response =
      get(
        authorized(tokens.token),
        "/api/v1/roles/#{target_role.role_id}/users",
        %{"allocated" => "true", "username" => allocated.username}
      )

    assert %{
             "success" => true,
             "data" => %{"total" => 1, "rows" => [%{"userId" => ^allocated_id}]}
           } = json_response(allocated_response, 200)

    unallocated_response =
      get(
        authorized(tokens.token),
        "/api/v1/roles/#{target_role.role_id}/users",
        %{"allocated" => "false", "username" => unallocated.username}
      )

    assert %{
             "success" => true,
             "data" => %{"total" => 1, "rows" => [%{"userId" => ^unallocated_id}]}
           } = json_response(unallocated_response, 200)
  end

  @tag :integration
  test "role batch delete rolls back missing targets and deduplicates IDs" do
    actor_role = create_role("TENANT")
    grant_permission(actor_role.role_id, "role:delete")
    first_role = create_role("TENANT")
    second_role = create_role("TENANT")
    missing_id = Identity.v7()
    actor = create_user(actor_role.role_id)
    {:ok, tokens} = Auth.login_plaintext(actor.username, "Strong!123")

    rejected =
      delete(
        authorized(tokens.token),
        "/api/v1/roles",
        %{"role_ids" => Enum.join([first_role.role_id, missing_id, second_role.role_id], ",")}
      )

    assert get_in(json_response(rejected, 404), ["error", "code"]) == "validation_failed"
    assert Repo.get!(SysRole, first_role.role_id).deleted == false
    assert Repo.get!(SysRole, second_role.role_id).deleted == false

    success =
      delete(
        authorized(tokens.token),
        "/api/v1/roles",
        %{
          "role_ids" =>
            Enum.join([first_role.role_id, first_role.role_id, second_role.role_id], ",")
        }
      )

    assert get_in(json_response(success, 200), ["data", "deleted"]) == 2
    assert Repo.get!(SysRole, first_role.role_id).deleted == true
    assert Repo.get!(SysRole, second_role.role_id).deleted == true
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
