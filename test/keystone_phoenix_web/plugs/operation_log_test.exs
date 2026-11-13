defmodule KeystonePhoenixWeb.Plugs.OperationLogTest do
  use KeystonePhoenix.DataCase, async: false

  import Ecto.Query
  import Plug.Conn
  import Plug.Test

  alias KeystonePhoenix.Log.SysOperationLog
  alias KeystonePhoenix.Log
  alias KeystonePhoenix.Repo
  alias KeystonePhoenix.User.SysUser
  alias KeystonePhoenixWeb.Plugs.OperationLog

  test "records a sanitized authenticated write request" do
    user_id = "018f2a7e-5d3c-7b01-8a11-000000000131"

    %SysUser{user_id: user_id}
    |> SysUser.create_changeset(%{username: unique("operation_actor"), password: "Strong!123"})
    |> Repo.insert!()

    conn =
      :put
      |> conn("/api/v1/system/user/profile", "")
      |> Map.put(:params, %{
        "nickName" => "审计用户",
        "password" => "do-not-persist",
        "refreshToken" => "do-not-persist",
        "captchaCodeKey" => "one-time-key"
      })
      |> assign(:current_user, %SysUser{
        user_id: user_id,
        username: "tester"
      })
      |> Map.put(:private, %{
        phoenix_controller: KeystonePhoenixWeb.ProfileController,
        phoenix_action: :update
      })
      |> OperationLog.call([])

    _conn = send_resp(conn, 200, "ok")

    log = Repo.one(from entry in SysOperationLog, order_by: [desc: entry.operation_id])

    assert log.request_module == "KeystonePhoenixWeb.ProfileController"
    assert log.called_method == "KeystonePhoenixWeb.ProfileController.update"
    assert log.request_url == "/api/v1/system/user/profile"
    assert log.request_method == 3
    assert log.business_type == 2
    assert log.status == 1
    assert log.operation_result == "HTTP 200"
    assert log.operation_param =~ "审计用户"
    assert log.operation_param =~ "[REDACTED]"
    refute log.operation_param =~ "do-not-persist"
    refute log.operation_param =~ "one-time-key"
  end

  test "bounds operation and login log fields before persistence" do
    user_id = "018f2a7e-5d3c-7b01-8a11-000000000132"

    user =
      %SysUser{user_id: user_id}
      |> SysUser.create_changeset(%{username: unique("operation_bounds"), password: "Strong!123"})
      |> Repo.insert!()
      |> Map.put(:username, String.duplicate("u", 100))

    assert {:ok, log} =
             Log.create_operation_log(
               %{
                 "requestModule" => String.duplicate("m", 100),
                 "operationParam" => String.duplicate("p", 3_000),
                 "operationResult" => String.duplicate("r", 3_000),
                 "errorStack" => String.duplicate("e", 3_000)
               },
               user,
               String.duplicate("/", 300),
               "POST"
             )

    assert byte_size(log.request_module) <= 64
    assert byte_size(log.request_url) <= 256
    assert byte_size(log.username) <= 32
    assert byte_size(log.operation_param) <= 2_048
    assert byte_size(log.operation_result) <= 2_048
    assert byte_size(log.error_stack) <= 2_048

    assert :ok = Log.record_login_event(String.duplicate("u", 100), 0, String.duplicate("m", 300))

    login =
      Repo.one!(from entry in KeystonePhoenix.Log.SysLoginInfo, order_by: [desc: entry.info_id])

    assert byte_size(login.username) <= 50
    assert byte_size(login.msg) <= 255
  end

  defp unique(prefix), do: "#{prefix}_#{System.unique_integer([:positive])}"
end
