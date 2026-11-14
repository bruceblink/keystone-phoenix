defmodule KeystonePhoenix.RolePermissionAssignmentTest do
  use KeystonePhoenix.DataCase, async: false

  alias KeystonePhoenix.Identity
  alias KeystonePhoenix.Menu
  alias KeystonePhoenix.Repo
  alias KeystonePhoenix.Role
  alias KeystonePhoenix.Role.Permissions
  alias KeystonePhoenix.User.SysUser

  test "role writes explicit permissions used by authorization" do
    actor = %{
      user_id: Identity.v7(),
      data_scope: "ALL",
      permissions: [
        "permission:manage",
        "role:create",
        "role:read",
        "role:update",
        "role:manage"
      ]
    }

    authorization = [authorization: %{principal: actor, permission: "role:create"}]

    assert {:ok, role} =
             Role.create_role(
               %{
                 "roleName" => "显式权限角色",
                 "roleKey" => unique("explicit_permissions"),
                 "roleSort" => 1,
                 "dataScope" => "ALL",
                 "status" => 1,
                 "permissions" => ["user:read", "role:read"]
               },
               authorization
             )

    assert {:ok, permissions} = Permissions.list_for_role(role.role_id, authorization)
    assert permissions == ["role:read", "user:read"]

    user =
      %SysUser{}
      |> SysUser.create_changeset(%{
        user_id: Identity.v7(),
        username: unique("explicit_permission_user"),
        password: "Strong!123",
        role_id: role.role_id,
        status: 1
      })
      |> Repo.insert!()

    assert "user:read" in Menu.permissions_for_user(user)
    assert "role:read" in Menu.permissions_for_user(user)

    assert {:ok, _updated} =
             Role.update_role(
               role.role_id,
               %{"permissions" => ["department:read"]},
               authorization: %{principal: actor, permission: "role:update"}
             )

    assert Menu.permissions_for_user(%{role_id: role.role_id}) == ["department:read"]
  end

  defp unique(prefix), do: "#{prefix}_#{System.unique_integer([:positive])}"
end
