defmodule KeystonePhoenix.AuthzTest do
  use ExUnit.Case, async: true

  alias KeystonePhoenix.Authz
  alias KeystonePhoenix.Authz.Principal

  test "normalizes API user fields into a principal" do
    principal =
      Principal.from_user(%{
        "userId" => 42,
        "roleId" => 7,
        "deptId" => 3,
        "isAdmin" => 0,
        "sessionId" => "session-1",
        "permissions" => ["system:user:list"]
      })

    assert principal.subject_id == 42
    assert principal.roles == [7]
    assert principal.department_id == 3
    assert principal.session_id == "session-1"
    refute principal.is_admin
    assert principal.raw["userId"] == 42
  end

  test "falls back from nil atom fields to API-shaped string fields" do
    principal =
      Principal.from_user(%{
        "userId" => 42,
        "roleId" => 7,
        "deptId" => 3,
        "isAdmin" => 1,
        user_id: nil,
        role_id: nil,
        dept_id: nil,
        is_admin: nil
      })

    assert principal.subject_id == 42
    assert principal.roles == [7]
    assert principal.department_id == 3
    assert principal.is_admin
  end

  test "checks exact permission strings and administrator compatibility" do
    principal = Principal.from_user(%{user_id: 1, permissions: ["system:user:list"]})

    assert Authz.allowed?(principal, "system:user:list")
    refute Authz.allowed?(principal, "system:user:edit")
    assert Authz.allowed?(%{is_admin: true}, "system:anything")
    assert Authz.allowed?(%{"isAdmin" => "1"}, "system:anything")
  end

  test "defaults to deny for missing or malformed permission input" do
    refute Authz.allowed?(%{}, "")
    refute Authz.allowed?(%{}, :missing)
    assert {:error, :permission_denied} = Authz.authorize(%{}, "")

    assert {:error, :data_scope_denied} =
             Authz.authorize(%{permissions: ["system:user:edit"]}, "system:user:edit", 1, %{
               scope: :unknown
             })
  end

  test "returns stable authorization errors" do
    actor = %{user_id: 1, permissions: ["system:user:edit"]}

    assert :ok = Authz.authorize(actor, "system:user:edit")
    assert {:error, :permission_denied} = Authz.authorize(actor, "system:user:remove")

    assert {:error, :data_scope_denied} =
             Authz.authorize(actor, "system:user:edit", 9, %{scope: :users})
  end

  test "none scope is always allowed after the permission check" do
    actor = %{permissions: ["system:job:run"]}
    assert :ok = Authz.authorize(actor, "system:job:run", nil, %{scope: :none})
  end

  test "self scope is limited to the principal subject" do
    assert Authz.scope_allowed?(%{user_id: 42}, :self, 42)
    refute Authz.scope_allowed?(%{user_id: 42}, :self, 43)
    assert Authz.scope_allowed?(%{is_admin: true}, :self, 43)
  end
end
