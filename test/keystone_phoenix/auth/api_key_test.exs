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
  alias KeystonePhoenix.User.SysUserRole

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

  test "rejects API Key expiry beyond the 90-day limit with a specific reason" do
    # 超期判断在访问用户和数据库前完成，因此使用有效 UUID 即可验证服务错误原因。
    expiry = DateTime.add(DateTime.utc_now(), 91 * 24 * 60 * 60, :second)

    assert {:error, :api_key_expiry_out_of_range} =
             ApiKey.issue(Identity.v7(), "long-lived worker", ["api-key:read"], expiry)
  end

  test "API Key issue reports specific name and expiry validation reasons" do
    user_id = Identity.v7()

    assert {:error, :api_key_name_invalid} =
             ApiKey.issue(user_id, "  ", ["api-key:read"])

    assert {:error, :api_key_name_invalid} =
             ApiKey.issue(user_id, String.duplicate("a", 129), ["api-key:read"])

    assert {:error, :api_key_expiry_invalid} =
             ApiKey.issue(user_id, "worker", ["api-key:read"], "not a date")
  end

  test "multi-role scopes use the permission union and shrink after role revocation" do
    primary = create_role(["api-key:create", "api-key:read", "user:read"])
    secondary = create_role(["user:update"])
    user = create_multi_role_user(primary, secondary)

    assert {:ok, issued} =
             ApiKey.issue(user.user_id, "multi-role worker", ["user:read", "user:update"])

    assert {:ok, principal} = ApiKey.authenticate(issued.api_key, "127.0.0.10")
    assert principal.scopes == ["user:read", "user:update"]

    assert {:error, :scope_exceeds_permissions} =
             ApiKey.issue(user.user_id, "unsupported worker", ["user:delete"])

    Repo.delete_all(
      from membership in SysUserRole,
        where: membership.user_id == ^user.user_id and membership.role_id == ^secondary.role_id
    )

    assert {:ok, reduced} = ApiKey.authenticate(issued.api_key, "127.0.0.10")
    assert reduced.scopes == ["user:read"]

    revoke_role_permission(primary.role_id, "user:read")
    assert {:error, :permission_denied} = ApiKey.authenticate(issued.api_key, "127.0.0.10")
  end

  test "new roles do not expand approved scopes and rotation re-intersects current roles" do
    primary = create_role(["api-key:create", "api-key:rotate", "user:read"])
    secondary = create_role(["user:update"])
    user = create_multi_role_user(primary, secondary)

    assert {:ok, issued} =
             ApiKey.issue(user.user_id, "bounded worker", ["user:read", "user:update"])

    extra = create_role(["user:delete"])

    Repo.insert!(%SysUserRole{user_id: user.user_id, role_id: extra.role_id})

    assert {:ok, unchanged} = ApiKey.authenticate(issued.api_key, "127.0.0.11")
    assert unchanged.scopes == ["user:read", "user:update"]

    Repo.delete_all(
      from membership in SysUserRole,
        where: membership.user_id == ^user.user_id and membership.role_id == ^secondary.role_id
    )

    assert {:ok, replacement} = ApiKey.rotate(user.user_id, issued.id)
    assert replacement.scopes == ["user:read"]
    assert {:error, :invalid_credential} = ApiKey.authenticate(issued.api_key, "127.0.0.11")
    assert {:ok, rotated} = ApiKey.authenticate(replacement.api_key, "127.0.0.11")
    assert rotated.scopes == ["user:read"]
  end

  test "authenticates, revokes and rejects an expired key" do
    user = create_user(@permissions)
    assert {:ok, issued} = ApiKey.issue(user.user_id, "worker", ["api-key:read"])

    assert {:ok, principal} = ApiKey.authenticate(issued.api_key, "127.0.0.1")
    assert principal.credential_type == "API_KEY"
    assert principal.credential_id == issued.id
    assert principal.subject_type == "SERVICE_SUBJECT"
    assert principal.approved_scopes == ["api-key:read"]
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
    role = create_role(permissions)

    create_user_for_role(role)
  end

  defp create_role(permissions) do
    role_id = Identity.v7()

    role =
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

    role
  end

  defp create_multi_role_user(primary, secondary) do
    user = create_user_for_role(primary)

    Repo.insert!(%SysUserRole{user_id: user.user_id, role_id: primary.role_id})
    Repo.insert!(%SysUserRole{user_id: user.user_id, role_id: secondary.role_id})
    user
  end

  defp create_user_for_role(role) do
    %SysUser{}
    |> SysUser.create_changeset(%{
      user_id: Identity.v7(),
      role_id: role.role_id,
      username: "api_key_#{System.unique_integer([:positive])}",
      password: "Strong!123",
      status: 1
    })
    |> Repo.insert!()
  end

  defp revoke_role_permission(role_id, permission) do
    entry = Repo.get_by!(SysPermission, permission: permission)

    Repo.delete_all(
      from role_permission in SysRolePermission,
        where:
          role_permission.role_id == ^role_id and
            role_permission.permission_id == ^entry.permission_id
    )
  end
end
