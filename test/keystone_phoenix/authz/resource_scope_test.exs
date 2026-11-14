defmodule KeystonePhoenix.Authz.ResourceScopeTest do
  use ExUnit.Case, async: true

  alias KeystonePhoenix.Authz.{DataScope, ResourceScope}
  alias KeystonePhoenix.Identity

  test "resource matrix registers self, relationship and global entry rules" do
    assert ResourceScope.registered?(:profile)
    assert ResourceScope.registered?("api-key")
    assert ResourceScope.rule(:profile).scopes == ["SELF"]
    assert ResourceScope.rule(:owned).scopes == ["OWNER", "MEMBER"]

    for resource <- ~w(role post menu config dictionary audit session file)a do
      assert ResourceScope.rule(resource).scopes == ["ALL", "TENANT"]
    end

    for resource <- ~w(job notice)a do
      assert ResourceScope.rule(resource).scopes == ["ALL", "TENANT", "OWNER"]
    end

    refute ResourceScope.registered?(:unknown)
    refute ResourceScope.allowed?(%{}, :unknown)

    assert DataScope.supported?("api-key", "SELF")
    assert DataScope.supported?(:owned, "OWNER")
    refute DataScope.supported?(:role, "DEPARTMENT")
  end

  test "self resources require the authenticated subject" do
    user_id = Identity.v7()
    principal = %{user_id: user_id, permissions: [], data_scope: "SELF"}

    assert ResourceScope.allowed?(principal, :profile)
    assert ResourceScope.allowed?(principal, :api_key)
    assert ResourceScope.allowed?(principal, :profile, %{target_id: user_id})
    refute ResourceScope.allowed?(principal, :profile, %{target_id: Identity.v7()})
    refute ResourceScope.allowed?(%{permissions: [], data_scope: "SELF"}, :profile)
  end

  test "owned resources use OWNER or MEMBER relationships" do
    user_id = Identity.v7()
    owner_id = Identity.v7()
    member_id = Identity.v7()
    principal = %{user_id: user_id, permissions: []}

    assert ResourceScope.allowed?(%{user_id: owner_id, permissions: []}, :owned, %{
             owner_id: owner_id
           })

    assert ResourceScope.allowed?(principal, :owned, %{
             owner_id: owner_id,
             member_ids: [member_id, user_id]
           })

    refute ResourceScope.allowed?(principal, :owned, %{
             owner_id: owner_id,
             member_ids: [member_id]
           })
  end

  test "global resources accept only ALL or TENANT" do
    for scope <- ["ALL", "TENANT"] do
      principal = %{user_id: Identity.v7(), permissions: [], data_scope: scope}
      assert ResourceScope.allowed?(principal, :role)
      assert ResourceScope.allowed?(principal, :file)
    end

    for scope <- ["SELF", "OWNER", "MEMBER", "DEPARTMENT", "CUSTOM"] do
      principal = %{user_id: Identity.v7(), permissions: [], data_scope: scope}
      refute ResourceScope.allowed?(principal, :role)
      refute ResourceScope.allowed?(principal, :file)
    end
  end

  test "owner resources return an owner query scope" do
    user_id = Identity.v7()
    principal = %{user_id: user_id, permissions: [], data_scope: "OWNER"}

    assert {:ok, {:owner, ^user_id}} = ResourceScope.owner_scope(principal, :notice)
    assert {:ok, {:owner, ^user_id}} = ResourceScope.owner_scope(principal, :job)

    assert {:ok, :all} =
             ResourceScope.owner_scope(%{permissions: [], data_scope: "TENANT"}, :notice)

    assert {:error, :data_scope_denied} = ResourceScope.owner_scope(%{permissions: []}, :notice)
  end

  test "permission:manage keeps the administrator path" do
    principal = %{user_id: Identity.v7(), permissions: ["permission:manage"], data_scope: "SELF"}

    assert ResourceScope.allowed?(principal, :role)
    assert ResourceScope.allowed?(principal, :session)
  end
end
