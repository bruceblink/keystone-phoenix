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

  test "falls back to legacy menu permissions when catalog has no entry" do
    permission = "system:legacy:read_#{System.unique_integer([:positive])}"
    role = insert_role()

    menu_id =
      Repo.insert_all(
        "sys_menu",
        [
          %{
            menu_name: "兼容权限",
            menu_type: 0,
            parent_id: 0,
            permission: permission,
            status: 1,
            deleted: false,
            meta_info: "{}",
            create_time: DateTime.utc_now(),
            update_time: DateTime.utc_now()
          }
        ],
        returning: [:menu_id]
      )
      |> elem(1)
      |> List.first()
      |> Map.fetch!(:menu_id)

    Repo.insert_all("sys_role_menu", [%{role_id: role.role_id, menu_id: menu_id}])

    assert Authz.allowed?(%{role_id: role.role_id}, permission)
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
