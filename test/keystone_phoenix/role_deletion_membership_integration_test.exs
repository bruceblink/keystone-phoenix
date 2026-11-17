defmodule KeystonePhoenix.RoleDeletionMembershipIntegrationTest do
  use KeystonePhoenix.DataCase, async: false

  @moduletag :integration

  alias KeystonePhoenix.Repo
  alias KeystonePhoenix.Role
  alias KeystonePhoenix.Role.SysRole
  alias KeystonePhoenix.User
  alias KeystonePhoenix.User.SysUser
  alias KeystonePhoenix.User.SysUserRole

  # 使用真实 Repo 写入主角色和关联角色，验证删除检查读取两种成员关系。
  test "primary role assignment blocks deletion" do
    role = create_role("role_delete_primary")
    user = create_user(role.role_id)

    assert {:error, :has_users} = Role.delete_role(role.role_id, admin_auth("role:delete"))
    refute Repo.get!(SysUser, user.user_id).deleted
    refute Repo.get!(SysRole, role.role_id).deleted
  end

  test "protected administrator role returns its own domain error even when it has users" do
    role = Repo.get_by!(SysRole, role_key: "admin", deleted: false)

    assert {:error, :protected_role} = Role.delete_role(role.role_id, admin_auth("role:delete"))
    refute Repo.get!(SysRole, role.role_id).deleted
  end

  test "secondary role membership blocks deletion" do
    primary_role = create_role("role_delete_owner")
    secondary_role = create_role("role_delete_secondary")
    user = create_user(primary_role.role_id)
    Repo.insert!(%SysUserRole{user_id: user.user_id, role_id: secondary_role.role_id})

    assert {:error, :has_users} =
             Role.delete_role(secondary_role.role_id, admin_auth("role:delete"))

    refute Repo.get!(SysRole, secondary_role.role_id).deleted
  end

  test "mixed role deletion rolls back when a secondary member is present" do
    primary_role = create_role("role_delete_batch_owner")
    empty_role = create_role("role_delete_batch_empty")
    secondary_role = create_role("role_delete_batch_secondary")
    user = create_user(primary_role.role_id)
    Repo.insert!(%SysUserRole{user_id: user.user_id, role_id: secondary_role.role_id})

    assert {:error, :has_users} =
             Role.delete_roles(
               [empty_role.role_id, secondary_role.role_id],
               admin_auth("role:delete")
             )

    refute Repo.get!(SysRole, empty_role.role_id).deleted
    refute Repo.get!(SysRole, secondary_role.role_id).deleted
  end

  test "soft-deleted secondary member does not block role deletion" do
    primary_role = create_role("role_delete_deleted_owner")
    secondary_role = create_role("role_delete_deleted_secondary")
    user = create_user(primary_role.role_id)
    Repo.insert!(%SysUserRole{user_id: user.user_id, role_id: secondary_role.role_id})
    Repo.update!(Ecto.Changeset.change(user, deleted: true))

    assert {:ok, :ok} = Role.delete_role(secondary_role.role_id, admin_auth("role:delete"))
    assert Repo.get!(SysRole, secondary_role.role_id).deleted
  end

  defp create_role(prefix) do
    attrs = %{
      "roleName" => prefix,
      "roleKey" => unique(prefix),
      "roleSort" => 1,
      "dataScope" => "ALL",
      "status" => 1,
      "menuIds" => []
    }

    {:ok, role} = Role.create_role(attrs, admin_auth("role:create"))
    role
  end

  defp create_user(role_id) do
    {:ok, user} =
      User.create_user(
        %{
          "username" => unique("role_delete_user"),
          "password" => "Strong!123",
          "roleId" => role_id
        },
        authorization: %{
          principal: %{permissions: ["user:create", "role:assign", "permission:manage"]},
          permission: "user:create"
        }
      )

    user
  end

  defp admin_auth(permission),
    do: [
      authorization: %{
        principal: %{permissions: [permission, "permission:manage"]},
        permission: permission
      }
    ]

  defp unique(prefix), do: "#{prefix}_#{System.unique_integer([:positive])}"
end
