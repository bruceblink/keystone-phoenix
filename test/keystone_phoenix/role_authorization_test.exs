defmodule KeystonePhoenix.RoleAuthorizationTest do
  use KeystonePhoenix.DataCase, async: false

  alias KeystonePhoenix.Identity
  alias KeystonePhoenix.Repo
  alias KeystonePhoenix.Role
  alias KeystonePhoenix.Role.SysRole

  test "principal-aware role writes reject missing permission before updating" do
    role =
      %SysRole{}
      |> SysRole.changeset(%{
        role_name: "受保护角色",
        role_key: "protected_#{System.unique_integer([:positive])}",
        role_sort: 1,
        data_scope: "ALL",
        status: 1
      })
      |> Repo.insert!()

    assert {:error, :permission_denied} =
             Role.update_role(role.role_id, %{"roleName" => "不应写入"},
               authorization: %{
                 principal: %{user_id: 9010, permissions: []},
                 permission: "system:role:edit"
               }
             )

    assert Repo.get!(SysRole, role.role_id).role_name == "受保护角色"
  end

  test "department and self scoped principals cannot write global roles" do
    role = insert_role()
    user = insert_user()

    for scope <- ["DEPARTMENT", "SELF"] do
      authorization = scoped_authorization(scope)

      assert {:error, :data_scope_denied} =
               Role.create_role(
                 %{
                   "roleName" => "越权角色",
                   "roleKey" => "scope_denied_#{scope}",
                   "roleSort" => 1,
                   "status" => 1
                 },
                 authorization
               )

      assert {:error, :data_scope_denied} =
               Role.update_role(role.role_id, %{"roleName" => "不应写入"}, authorization)

      assert {:error, :data_scope_denied} = Role.delete_role(role.role_id, authorization)

      assert {:error, :data_scope_denied} =
               Role.change_status(role.role_id, 0, authorization)

      assert {:error, :data_scope_denied} =
               Role.update_data_scope(role.role_id, %{"dataScope" => "TENANT"}, authorization)

      assert {:error, :data_scope_denied} =
               Role.assign_users(role.role_id, [user.user_id], authorization)

      assert {:error, :data_scope_denied} = Role.unassign_users([user.user_id], authorization)
    end

    unchanged = Repo.get!(SysRole, role.role_id)
    assert unchanged.role_name == "权限角色"
    assert unchanged.status == 1
    assert is_nil(Repo.get!(KeystonePhoenix.User.SysUser, user.user_id).role_id)
  end

  test "scoped role menu reads use the same resource scope rule" do
    role = insert_role()

    assert {:error, :data_scope_denied} =
             Role.menu_ids_for_role(role.role_id, scoped_authorization("DEPARTMENT"))

    assert {:ok, []} =
             Role.menu_ids_for_role(
               role.role_id,
               authorization: %{
                 principal: %{data_scope: "TENANT", permissions: ["role:read"]}
               }
             )
  end

  defp insert_role do
    %SysRole{}
    |> SysRole.changeset(%{
      role_name: "权限角色",
      role_key: "scope_role_#{System.unique_integer([:positive])}",
      role_sort: 1,
      data_scope: "ALL",
      status: 1
    })
    |> Repo.insert!()
  end

  defp insert_user do
    %KeystonePhoenix.User.SysUser{}
    |> KeystonePhoenix.User.SysUser.create_changeset(%{
      username: "scope_user_#{System.unique_integer([:positive])}",
      password: "Strong!123"
    })
    |> Repo.insert!()
  end

  defp scoped_authorization(scope) do
    [
      authorization: %{
        principal: %{
          user_id: Identity.v7(),
          data_scope: scope,
          permissions: [
            "role:read",
            "role:create",
            "role:update",
            "role:delete",
            "role:manage",
            "role:assign"
          ]
        }
      }
    ]
  end
end
