defmodule KeystonePhoenix.Authz.NormalizedPolicyTest do
  use KeystonePhoenix.DataCase, async: false

  alias KeystonePhoenix.Authz
  alias KeystonePhoenix.Authz.{SysPermission, SysRolePermission}
  alias KeystonePhoenix.Repo
  alias KeystonePhoenix.Role.SysRole

  test "uses normalized role permission bindings when present" do
    permission = "system:normalized:read_#{System.unique_integer([:positive])}"

    role =
      %SysRole{}
      |> SysRole.changeset(%{
        role_name: "规范权限角色",
        role_key: "normalized_#{System.unique_integer([:positive])}",
        role_sort: 1,
        data_scope: 1,
        status: 1
      })
      |> Repo.insert!()

    entry =
      %SysPermission{}
      |> Ecto.Changeset.change(%{
        permission: permission,
        resource: "system",
        domain: "normalized",
        action: "read",
        risk: "low",
        status: 1,
        deprecated: false
      })
      |> Repo.insert!()

    Repo.insert!(%SysRolePermission{role_id: role.role_id, permission_id: entry.permission_id})

    assert Authz.allowed?(%{role_id: role.role_id}, permission)
  end

  test "does not authorize from legacy menu permissions" do
    permission = "system:legacy:read_#{System.unique_integer([:positive])}"
    role = insert_role()

    refute Authz.allowed?(%{role_id: role.role_id}, permission)
  end

  defp insert_role do
    %SysRole{}
    |> SysRole.changeset(%{
      role_name: "旧权限角色",
      role_key: "legacy_#{System.unique_integer([:positive])}",
      role_sort: 1,
      data_scope: 1,
      status: 1
    })
    |> Repo.insert!()
  end
end
