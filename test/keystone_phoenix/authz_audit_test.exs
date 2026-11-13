defmodule KeystonePhoenix.AuthzAuditTest do
  use KeystonePhoenix.DataCase, async: false

  import Ecto.Query

  alias KeystonePhoenix.Authz
  alias KeystonePhoenix.Log.SysOperationLog
  alias KeystonePhoenix.Repo
  alias KeystonePhoenix.User.SysUser

  test "persists a sanitized authorization decision" do
    actor_id = "018f2a7e-5d3c-7b01-8a11-000000000121"

    %SysUser{user_id: actor_id}
    |> SysUser.create_changeset(%{username: unique("authz_actor"), password: "Strong!123"})
    |> Repo.insert!()

    assert {:error, :permission_denied} =
             Authz.authorize(
               %{user_id: actor_id, permissions: []},
               "user:update",
               "018f2a7e-5d3c-7b01-8a11-000000000122",
               %{
                 session_id: "session-42",
                 tenant_id: "tenant-7",
                 resource_id: "018f2a7e-5d3c-7b01-8a11-000000000123",
                 request_id: "req-42"
               }
             )

    log =
      Repo.one!(
        from entry in SysOperationLog,
          where: entry.request_module == "KeystonePhoenix.Authz",
          order_by: [desc: entry.operation_id]
      )

    assert log.called_method == "user:update"
    assert log.operation_result == "permission_denied"
    assert log.status == 0
    assert log.operation_param =~ actor_id
    assert log.operation_param =~ "session-42"
    assert log.operation_param =~ "tenantId"
    assert log.operation_param =~ "resourceId"
    assert log.operation_param =~ "requestId"
    refute log.operation_param =~ "password"
    refute log.operation_param =~ "token"
  end

  defp unique(prefix), do: "#{prefix}_#{System.unique_integer([:positive])}"
end
