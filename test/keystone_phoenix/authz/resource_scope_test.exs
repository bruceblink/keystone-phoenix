defmodule KeystonePhoenix.Authz.ResourceScopeTest do
  use ExUnit.Case, async: true

  alias KeystonePhoenix.Authz.{DataScope, Principal, ResourceScope}
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

  # 查询过滤型列表可进入，但通用入口不得把它解释为具体目标授权。
  test "query-filtered resources report list capability without broadening generic gates" do
    principal = %{user_id: Identity.v7(), permissions: [], data_scope: "ALL"}

    assert ResourceScope.rule(:user).kind == :query_filtered
    assert ResourceScope.rule(:department).kind == :query_filtered
    assert ResourceScope.allowed_for_scopes?(:user, [])
    assert ResourceScope.allowed_for_scopes?(:department, ["SELF"])
    refute ResourceScope.allowed?(principal, :user)
    refute ResourceScope.allowed?(principal, :department)
    refute ResourceScope.allowed_for_scopes?(:unknown, ["ALL"])
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

  # 本人资源必须同时满足主体匹配和 SELF 或全局数据范围。
  test "self resources accept SELF and global scopes but reject OWNER and empty scopes" do
    user_id = Identity.v7()

    for scope <- ["SELF", "ALL", "TENANT"] do
      assert ResourceScope.allowed?(%{user_id: user_id, data_scope: scope}, :profile)
      assert ResourceScope.allowed?(%{user_id: user_id, data_scope: scope}, :api_key)
    end

    for scope <- ["OWNER", "MEMBER", "DEPARTMENT", ""] do
      refute ResourceScope.allowed?(%{user_id: user_id, data_scope: scope}, :profile)
      refute ResourceScope.allowed?(%{user_id: user_id, data_scope: scope}, :api_key)
    end

    refute ResourceScope.allowed?(%{user_id: user_id, data_scope: "SELF"}, :profile, %{
             target_id: Identity.v7()
           })
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

  test "API Key owner scopes use the owner user ID and preserve the service subject" do
    user_id = Identity.v7()
    service_subject_id = Identity.v7()

    api_key = %{
      credential_type: "API_KEY",
      user_id: user_id,
      subject_id: service_subject_id,
      permissions: [],
      data_scope: "OWNER"
    }

    principal = Principal.from_user(api_key)

    assert principal.subject_id == service_subject_id
    assert Principal.scope_subject_id(principal) == user_id
    assert {:ok, {:owner, ^user_id}} = ResourceScope.owner_scope(principal, :notice)
    assert ResourceScope.allowed?(api_key, :job, %{owner_id: user_id})
    refute ResourceScope.allowed?(api_key, :job, %{owner_id: Identity.v7()})

    self_scoped_key = Map.put(api_key, :data_scope, "SELF")
    assert ResourceScope.allowed?(self_scoped_key, :profile, %{target_id: user_id})
    refute ResourceScope.allowed?(Map.delete(self_scoped_key, :user_id), :profile)
  end

  test "permission:manage keeps metadata capability but follows role data scope" do
    owner_id = Identity.v7()
    owner_admin = %{user_id: owner_id, permissions: ["permission:manage"], data_scope: "OWNER"}

    assert Principal.admin?(owner_admin)
    refute ResourceScope.allowed?(owner_admin, :role)
    assert {:ok, {:owner, ^owner_id}} = ResourceScope.owner_scope(owner_admin, :job)

    self_admin = %{user_id: owner_id, permissions: ["permission:manage"], data_scope: "SELF"}
    assert Principal.admin?(self_admin)
    refute ResourceScope.allowed?(self_admin, :role)
    assert {:error, :data_scope_denied} = ResourceScope.owner_scope(self_admin, :notice)

    all_admin = %{user_id: owner_id, permissions: ["permission:manage"], data_scope: "ALL"}
    assert Principal.admin?(all_admin)
    assert ResourceScope.allowed?(all_admin, :role)
    assert ResourceScope.allowed?(all_admin, :session)
    assert {:ok, :all} = ResourceScope.owner_scope(all_admin, :notice)
  end
end
