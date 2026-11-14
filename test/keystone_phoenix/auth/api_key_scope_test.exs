defmodule KeystonePhoenix.Auth.ApiKeyScopeTest do
  use KeystonePhoenix.DataCase, async: false

  alias KeystonePhoenix.Auth.ApiKey
  alias KeystonePhoenix.Authz.{SysPermission, SysRolePermission}
  alias KeystonePhoenix.Identity
  alias KeystonePhoenix.Repo
  alias KeystonePhoenix.Role.SysRole
  alias KeystonePhoenix.User.SysUser

  @permissions ["api-key:create", "api-key:read", "api-key:revoke", "api-key:rotate"]

  test "management commands require a SELF subject and reject API Key principals" do
    owner = create_user()
    other = create_user()
    wrong_subject = options(other.user_id)

    machine = [
      authorization: %{
        principal: %{
          user_id: owner.user_id,
          data_scope: "TENANT",
          credential_type: "API_KEY",
          permissions: @permissions
        }
      }
    ]

    assert {:error, :data_scope_denied} =
             ApiKey.issue(owner.user_id, "wrong subject", ["api-key:read"], nil, wrong_subject)

    assert {:error, :data_scope_denied} = ApiKey.list(owner.user_id, wrong_subject)

    assert {:error, :permission_denied} = ApiKey.list(owner.user_id, machine)
  end

  test "tenant-scoped human context supports API Key lifecycle" do
    owner = create_user()
    authorization = options(owner.user_id)

    assert {:ok, issued} =
             ApiKey.issue(owner.user_id, "scope worker", ["api-key:read"], nil, authorization)

    assert {:ok, listed} = ApiKey.list(owner.user_id, authorization)
    assert Enum.any?(listed, &(&1.id == issued.id))
    assert {:ok, replacement} = ApiKey.rotate(owner.user_id, issued.id, authorization)
    assert replacement.id != issued.id
    assert :ok = ApiKey.revoke(owner.user_id, replacement.id, authorization)
  end

  test "management commands require an explicit authorization context" do
    owner = create_user()

    assert {:error, :authorization_required} =
             ApiKey.issue(owner.user_id, "missing", ["api-key:read"], nil, [])

    assert {:error, :authorization_required} = ApiKey.list(owner.user_id, [])
    assert {:error, :authorization_required} = ApiKey.rotate(owner.user_id, Identity.v7(), [])
    assert {:error, :authorization_required} = ApiKey.revoke(owner.user_id, Identity.v7(), [])
  end

  defp options(user_id) do
    [
      authorization: %{
        principal: %{user_id: user_id, data_scope: "TENANT", permissions: @permissions}
      }
    ]
  end

  defp create_user do
    role_id = Identity.v7()

    %SysRole{}
    |> Ecto.Changeset.change(%{
      role_id: role_id,
      role_name: "API Key scope role",
      role_key: "api_key_scope_#{System.unique_integer([:positive])}",
      role_sort: 1,
      data_scope: "ALL",
      status: 1,
      deleted: false
    })
    |> Repo.insert!()

    Enum.each(@permissions, fn permission ->
      entry = Repo.get_by!(SysPermission, permission: permission)
      Repo.insert!(%SysRolePermission{role_id: role_id, permission_id: entry.permission_id})
    end)

    %SysUser{}
    |> SysUser.create_changeset(%{
      user_id: Identity.v7(),
      role_id: role_id,
      username: "api_key_scope_#{System.unique_integer([:positive])}",
      password: "Strong!123",
      status: 1
    })
    |> Repo.insert!()
  end
end
