defmodule KeystonePhoenix.Auth.ApiKeyTest do
  use KeystonePhoenix.DataCase, async: false

  import Ecto.Query

  alias KeystonePhoenix.Auth.ApiKey
  alias KeystonePhoenix.Auth.ApiKey.Key
  alias KeystonePhoenix.Authz.{SysPermission, SysRolePermission}
  alias KeystonePhoenix.Identity
  alias KeystonePhoenix.Repo
  alias KeystonePhoenix.Role.SysRole
  alias KeystonePhoenix.User.SysUser

  @permissions ["api-key:create", "api-key:read", "api-key:revoke", "api-key:rotate"]

  test "issues once-visible key material and stores only its digest" do
    user = create_user(@permissions)

    assert {:ok, issued} = ApiKey.issue(user.user_id, "build worker", ["api-key:read"])
    assert String.starts_with?(issued.api_key, "ks_live_")
    assert issued.scopes == ["api-key:read"]

    stored = Repo.get!(Key, issued.id)
    refute Map.has_key?(stored, :api_key)
    refute stored.key_hash == issued.api_key
    refute stored.key_hash =~ issued.api_key
    assert Enum.all?(ApiKey.list(user.user_id), &Map.has_key?(&1, :prefix))
  end

  test "rejects scopes outside current permissions" do
    user = create_user(["api-key:create", "api-key:read"])

    assert {:error, :scope_exceeds_permissions} =
             ApiKey.issue(user.user_id, "worker", ["api-key:read", "api-key:revoke"])
  end

  test "authenticates, revokes and rejects an expired key" do
    user = create_user(@permissions)
    assert {:ok, issued} = ApiKey.issue(user.user_id, "worker", ["api-key:read"])

    assert {:ok, principal} = ApiKey.authenticate(issued.api_key, "127.0.0.1")
    assert principal.credential_type == "API_KEY"
    assert principal.scopes == ["api-key:read"]
    assert :ok = ApiKey.revoke(user.user_id, issued.id)
    assert {:error, :invalid_credential} = ApiKey.authenticate(issued.api_key, "127.0.0.1")

    assert {:ok, expiring} =
             ApiKey.issue(
               user.user_id,
               "expiring",
               ["api-key:read"],
               DateTime.add(DateTime.utc_now(), 60, :second)
             )

    Repo.update_all(
      from(key in Key, where: key.id == ^expiring.id),
      set: [expires_at: DateTime.add(DateTime.utc_now(), -1, :second)]
    )

    assert {:error, :invalid_credential} = ApiKey.authenticate(expiring.api_key, "127.0.0.2")
  end

  test "rotation atomically revokes the old key" do
    user = create_user(@permissions)
    assert {:ok, issued} = ApiKey.issue(user.user_id, "worker", ["api-key:read"])

    assert {:ok, replacement} = ApiKey.rotate(user.user_id, issued.id)
    assert replacement.id != issued.id
    assert {:error, :invalid_credential} = ApiKey.authenticate(issued.api_key, "127.0.0.3")
    assert {:ok, principal} = ApiKey.authenticate(replacement.api_key, "127.0.0.3")
    assert principal.key_id == replacement.id
    assert Repo.get!(Key, issued.id).rotated_to == replacement.id
    assert {:error, :already_revoked} = ApiKey.rotate(user.user_id, issued.id)
  end

  test "concurrent rotations permit one replacement" do
    user = create_user(@permissions)
    assert {:ok, issued} = ApiKey.issue(user.user_id, "worker", ["api-key:read"])
    parent = self()

    tasks =
      for _ <- 1..2 do
        Task.async(fn ->
          Ecto.Adapters.SQL.Sandbox.allow(Repo, parent, self())
          ApiKey.rotate(user.user_id, issued.id)
        end)
      end

    results = Enum.map(tasks, &Task.await(&1, 5_000))
    assert Enum.count(results, &match?({:ok, _}, &1)) == 1
    assert Enum.count(results, &match?({:error, :already_revoked}, &1)) == 1
  end

  test "rate limits repeated invalid credentials by source and key" do
    invalid = "ks_live_aaaaaaaa_" <> String.duplicate("b", 43)

    for _ <- 1..20 do
      assert {:error, :invalid_credential} = ApiKey.authenticate(invalid, "10.0.0.8")
    end

    assert {:error, :rate_limited} = ApiKey.authenticate(invalid, "10.0.0.8")
  end

  defp create_user(permissions) do
    role_id = Identity.v7()

    %SysRole{}
    |> Ecto.Changeset.change(%{
      role_id: role_id,
      role_name: "API Key role",
      role_key: "api_key_#{System.unique_integer([:positive])}",
      role_sort: 1,
      data_scope: "ALL",
      status: 1,
      deleted: false
    })
    |> Repo.insert!()

    Enum.each(permissions, fn permission ->
      entry = Repo.get_by!(SysPermission, permission: permission)
      Repo.insert!(%SysRolePermission{role_id: role_id, permission_id: entry.permission_id})
    end)

    %SysUser{}
    |> SysUser.create_changeset(%{
      user_id: Identity.v7(),
      role_id: role_id,
      username: "api_key_#{System.unique_integer([:positive])}",
      password: "Strong!123",
      status: 1
    })
    |> Repo.insert!()
  end
end
