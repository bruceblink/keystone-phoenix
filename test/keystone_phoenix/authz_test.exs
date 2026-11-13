defmodule KeystonePhoenix.AuthzTest do
  use ExUnit.Case, async: true

  alias KeystonePhoenix.Authz
  alias KeystonePhoenix.Authz.Principal

  @user_id "018f2a7e-5d3c-7b01-8a11-000000000001"
  @role_id "018f2a7e-5d3c-7b01-8a11-000000000002"
  @dept_id "018f2a7e-5d3c-7b01-8a11-000000000003"

  test "normalizes API user fields into a principal" do
    principal =
      Principal.from_user(%{
        "userId" => @user_id,
        "roleId" => @role_id,
        "deptId" => @dept_id,
        "sessionId" => "session-1",
        "permissions" => ["user:read"]
      })

    assert principal.subject_id == @user_id
    assert principal.roles == [@role_id]
    assert principal.department_id == @dept_id
    assert principal.session_id == "session-1"
    assert principal.raw["userId"] == @user_id
  end

  test "falls back from nil atom fields to API-shaped string fields" do
    principal =
      Principal.from_user(%{
        "userId" => @user_id,
        "roleId" => @role_id,
        "deptId" => @dept_id,
        user_id: nil,
        role_id: nil,
        dept_id: nil
      })

    assert principal.subject_id == @user_id
    assert principal.roles == [@role_id]
    assert principal.department_id == @dept_id
  end

  test "checks exact catalog permissions without an administrator bypass" do
    principal =
      Principal.from_user(%{user_id: 1, permissions: ["user:read", "permission:manage"]})

    assert Authz.allowed?(principal, "user:read")
    refute Authz.allowed?(principal, "user:update")
    assert Authz.admin?(principal)
    refute Authz.allowed?(%{}, "user:update")
  end

  test "defaults to deny for missing or malformed permission input" do
    refute Authz.allowed?(%{}, "")
    refute Authz.allowed?(%{}, :missing)
    assert {:error, :permission_denied} = Authz.authorize(%{}, "")

    assert {:error, :data_scope_denied} =
             Authz.authorize(%{permissions: ["user:update"]}, "user:update", @user_id, %{
               scope: :unknown
             })
  end

  test "returns stable authorization errors" do
    actor = %{user_id: @user_id, permissions: ["user:update"]}

    assert :ok = Authz.authorize(actor, "user:update")
    assert {:error, :permission_denied} = Authz.authorize(actor, "user:delete")

    assert {:error, :data_scope_denied} =
             Authz.authorize(actor, "user:update", @role_id, %{scope: :users})
  end

  test "none scope is always allowed after the permission check" do
    actor = %{permissions: ["job:run"]}
    assert :ok = Authz.authorize(actor, "job:run", nil, %{scope: :none})
  end

  test "self scope is limited to the principal subject" do
    assert Authz.scope_allowed?(%{user_id: @user_id}, :self, @user_id)
    refute Authz.scope_allowed?(%{user_id: @user_id}, :self, @role_id)
    assert Authz.scope_allowed?(%{permissions: ["permission:manage"]}, :self, @role_id)
  end

  test "authorization decisions emit sanitized telemetry" do
    event = [:keystone_phoenix, :authz, :decision]
    handler = "authz-test-#{System.unique_integer([:positive])}"
    parent = self()

    :telemetry.attach(
      handler,
      event,
      fn ^event, measurements, metadata, _config ->
        send(parent, {:authz_decision, measurements, metadata})
      end,
      nil
    )

    on_exit(fn -> :telemetry.detach(handler) end)

    assert {:error, :permission_denied} =
             Authz.authorize(%{user_id: @user_id, permissions: []}, "user:update")

    assert_receive {:authz_decision, %{count: 1},
                    %{
                      outcome: :permission_denied,
                      permission: "user:update",
                      subject_id: @user_id
                    }}
  end
end
