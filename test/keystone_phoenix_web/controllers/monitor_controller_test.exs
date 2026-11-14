defmodule KeystonePhoenixWeb.MonitorControllerTest do
  use KeystonePhoenixWeb.ConnCase, async: false

  alias KeystonePhoenix.Auth
  alias KeystonePhoenix.Repo
  alias KeystonePhoenix.Role.SysRole
  alias KeystonePhoenix.User.SysUser

  test "security metrics and report use the audit permission and stable response shape" do
    role = Repo.get_by!(SysRole, role_key: "admin", deleted: false)

    user =
      %SysUser{}
      |> SysUser.create_changeset(%{
        username: "monitor_security_#{System.unique_integer([:positive])}",
        password: "Strong!123",
        role_id: role.role_id,
        status: 1
      })
      |> Repo.insert!()

    {:ok, tokens} = Auth.login_plaintext(user.username, "Strong!123")

    authorized = fn path ->
      build_conn()
      |> put_req_header("authorization", "Bearer #{tokens.token}")
      |> get(path)
    end

    metrics = authorized.("/api/v1/monitor/security")
    assert metrics.status == 200
    assert get_in(json_response(metrics, 200), ["data", "windowDays"]) == 30

    report = authorized.("/api/v1/monitor/security/report?horizonDays=7&pageSize=5")
    assert report.status == 200
    data = json_response(report, 200)["data"]
    assert data["tenantScope"] == "current"
    assert data["securityEvents"]["pageSize"] == 5

    invalid = authorized.("/api/v1/monitor/security/report?horizonDays=91")
    assert invalid.status == 422
    assert get_in(json_response(invalid, 422), ["error", "code"]) == "validation_failed"
  end
end
