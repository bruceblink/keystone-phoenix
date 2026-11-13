defmodule KeystonePhoenix.RoleAuthorizationTest do
  use KeystonePhoenix.DataCase, async: false

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
end
