defmodule KeystonePhoenix.Authz.NormalizedPolicyTest do
  use KeystonePhoenix.DataCase, async: false

  alias KeystonePhoenix.Authz
  alias KeystonePhoenix.Authz.{SysPermission, SysRolePermission}
  alias KeystonePhoenix.Identity
  alias KeystonePhoenix.Repo
  alias KeystonePhoenix.Role.SysRole

  test "uses normalized role permission bindings when present" do
    permission = "user:read"

    role =
      %SysRole{role_id: Identity.v7()}
      |> SysRole.changeset(%{
        role_name: "规范权限角色",
        role_key: "normalized_#{System.unique_integer([:positive])}",
        role_sort: 1,
        data_scope: "ALL",
        status: 1
      })
      |> Repo.insert!()

    entry = Repo.get_by!(SysPermission, permission: permission)

    Repo.insert!(%SysRolePermission{role_id: role.role_id, permission_id: entry.permission_id})

    assert Authz.allowed?(%{role_id: role.role_id}, permission)
  end

  test "does not authorize from legacy menu permissions" do
    permission = "legacy:read"
    role = insert_role()

    refute Authz.allowed?(%{role_id: role.role_id}, permission)
  end

  defp insert_role do
    %SysRole{role_id: Identity.v7()}
    |> SysRole.changeset(%{
      role_name: "旧权限角色",
      role_key: "legacy_#{System.unique_integer([:positive])}",
      role_sort: 1,
      data_scope: "ALL",
      status: 1
    })
    |> Repo.insert!()
  end
end
