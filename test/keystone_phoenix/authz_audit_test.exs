defmodule KeystonePhoenix.AuthzAuditTest do
  use KeystonePhoenix.DataCase, async: false

  import Ecto.Query

  alias KeystonePhoenix.Authz
  alias KeystonePhoenix.Log.SysOperationLog
  alias KeystonePhoenix.Repo

  test "persists a sanitized authorization decision" do
    assert {:error, :permission_denied} =
             Authz.authorize(
               %{user_id: 9002, permissions: []},
               "system:user:edit",
               42,
               %{session_id: "session-42", tenant_id: 7, resource_id: 42, request_id: "req-42"}
             )

    log =
      Repo.one!(
        from entry in SysOperationLog,
          where: entry.request_module == "KeystonePhoenix.Authz",
          order_by: [desc: entry.operation_id]
      )

    assert log.called_method == "system:user:edit"
    assert log.operation_result == "permission_denied"
    assert log.status == 0
    assert log.operation_param =~ "9002"
    assert log.operation_param =~ "session-42"
    assert log.operation_param =~ "tenantId"
    assert log.operation_param =~ "resourceId"
    assert log.operation_param =~ "requestId"
    refute log.operation_param =~ "password"
    refute log.operation_param =~ "token"
  end
end
