defmodule KeystonePhoenix.RoleScopeTest do
  use KeystonePhoenix.DataCase, async: false

  alias KeystonePhoenix.Identity
  alias KeystonePhoenix.Role

  test "role list and detail require the registered resource scope" do
    authorization = [
      authorization: %{
        principal: %{data_scope: "DEPARTMENT", permissions: ["role:read", "role:export"]}
      }
    ]

    assert {:error, :data_scope_denied} = Role.list_roles(%{}, authorization)
    assert {:error, :data_scope_denied} = Role.list_roles_for_export(%{}, authorization)
    assert {:error, :data_scope_denied} = Role.get_role(Identity.v7(), authorization)
    assert {:error, :authorization_required} = Role.get_role(Identity.v7(), [])
  end
end
