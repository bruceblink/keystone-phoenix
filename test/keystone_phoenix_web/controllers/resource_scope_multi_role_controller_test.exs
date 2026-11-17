defmodule KeystonePhoenixWeb.ResourceScopeMultiRoleControllerTest do
  use KeystonePhoenixWeb.ConnCase, async: false

  import Ecto.Query

  alias KeystonePhoenix.Auth

  alias KeystonePhoenix.Authz.{
    PolicyCache,
    Principal,
    ResourceScope,
    SysPermission,
    SysRolePermission
  }

  alias KeystonePhoenix.Identity
  alias KeystonePhoenix.Repo
  alias KeystonePhoenix.Role.SysRole
  alias KeystonePhoenix.User.{SysUser, SysUserRole}

  @tag :integration
  test "role member HTTP access uses the union of every enabled role scope" do
    for global_scope <- ["TENANT", "ALL"] do
      preferred_role = insert_role("DEPARTMENT")
      global_role = insert_role(global_scope)
      link_permission(global_role.role_id, "role:read")
      user = insert_user(preferred_role.role_id)
      link_user_role(user.user_id, preferred_role.role_id)
      link_user_role(user.user_id, global_role.role_id)
      {:ok, tokens} = Auth.login_plaintext(user.username, "Strong!123")

      response =
        get(
          authorized(build_conn(), tokens.token),
          "/api/v1/roles/#{global_role.role_id}/users",
          %{"allocated" => "true"}
        )

      assert %{"success" => true, "data" => [user_id]} = json_response(response, 200)
      assert user_id == user.user_id

      identity_response =
        get(
          authorized(build_conn(), tokens.token),
          "/api/v1/roles/#{global_role.role_id}/users",
          %{"allocated" => "true", "include" => "identity"}
        )

      assert %{"success" => true, "data" => [identity]} =
               json_response(identity_response, 200)

      assert identity == %{
               "id" => user.user_id,
               "username" => user.username,
               "displayName" => user.nickname
             }

      principal = %Principal{
        subject_id: user.user_id,
        roles: [preferred_role.role_id, global_role.role_id],
        permissions: ["role:read"],
        raw: %{}
      }

      assert ResourceScope.allowed?(principal, :role)

      # 模拟历史存量中的小写范围，验证入口读取时仍按规范范围判断。
      Repo.update_all(
        from(role in SysRole, where: role.role_id == ^global_role.role_id),
        set: [data_scope: String.downcase(global_scope)]
      )

      assert ResourceScope.allowed?(principal, :role)
    end
  end

  @tag :integration
  test "role member HTTP access is denied when no enabled role has a global scope" do
    preferred_role = insert_role("DEPARTMENT")
    other_role = insert_role("SELF")
    disabled_global_role = insert_role("ALL")

    disabled_global_role
    |> Ecto.Changeset.change(status: 0)
    |> Repo.update!()

    link_permission(preferred_role.role_id, "role:read")
    user = insert_user(preferred_role.role_id)
    link_user_role(user.user_id, preferred_role.role_id)
    link_user_role(user.user_id, other_role.role_id)
    link_user_role(user.user_id, disabled_global_role.role_id)
    {:ok, tokens} = Auth.login_plaintext(user.username, "Strong!123")

    response =
      get(
        authorized(build_conn(), tokens.token),
        "/api/v1/roles/#{other_role.role_id}/users",
        %{"allocated" => "true"}
      )

    assert get_in(json_response(response, 403), ["error", "code"]) == "data_scope_denied"

    identity_response =
      get(
        authorized(build_conn(), tokens.token),
        "/api/v1/roles/#{other_role.role_id}/users",
        %{"allocated" => "true", "include" => "identity"}
      )

    assert get_in(json_response(identity_response, 403), ["error", "code"]) ==
             "data_scope_denied"
  end

  defp authorized(conn, token), do: put_req_header(conn, "authorization", "Bearer #{token}")

  defp insert_role(data_scope) do
    %SysRole{}
    |> SysRole.changeset(%{
      role_name: "多角色范围测试",
      role_key: "multi_scope_#{System.unique_integer([:positive])}",
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
      username: "multi_scope_#{System.unique_integer([:positive])}",
      password: "Strong!123",
      status: 1
    })
    |> Repo.insert!()
  end

  # HTTP 授权需要首选角色与额外角色都存在于真实关联表。
  defp link_user_role(user_id, role_id) do
    Repo.insert!(%SysUserRole{user_id: user_id, role_id: role_id})
  end
end
