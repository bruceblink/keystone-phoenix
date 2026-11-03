defmodule KeystonePhoenixWeb.Plugs.OperationLogTest do
  use KeystonePhoenix.DataCase, async: false

  import Ecto.Query
  import Plug.Conn
  import Plug.Test

  alias KeystonePhoenix.Log.SysOperationLog
  alias KeystonePhoenix.Repo
  alias KeystonePhoenix.User.SysUser
  alias KeystonePhoenixWeb.Plugs.OperationLog

  test "records a sanitized authenticated write request" do
    conn =
      :put
      |> conn("/system/user/profile", "")
      |> Map.put(:params, %{
        "nickName" => "审计用户",
        "password" => "do-not-persist",
        "refreshToken" => "do-not-persist"
      })
      |> assign(:current_user, %SysUser{user_id: 42, username: "tester"})
      |> Map.put(:private, %{
        phoenix_controller: KeystonePhoenixWeb.ProfileController,
        phoenix_action: :update
      })
      |> OperationLog.call([])

    _conn = send_resp(conn, 200, "ok")

    log = Repo.one(from entry in SysOperationLog, order_by: [desc: entry.operation_id])

    assert log.request_module == "KeystonePhoenixWeb.ProfileController"
    assert log.called_method == "KeystonePhoenixWeb.ProfileController.update"
    assert log.request_url == "/system/user/profile"
    assert log.request_method == 3
    assert log.business_type == 2
    assert log.status == 1
    assert log.operation_result == "HTTP 200"
    assert log.operation_param =~ "审计用户"
    assert log.operation_param =~ "[REDACTED]"
    refute log.operation_param =~ "do-not-persist"
  end
end
