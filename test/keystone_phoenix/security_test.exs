defmodule KeystonePhoenix.SecurityTest do
  use KeystonePhoenix.DataCase, async: false

  alias KeystonePhoenix.Security

  test "security report returns bounded redacted operation events" do
    authorization = [
      authorization: %{
        principal: %{data_scope: "ALL", permissions: ["audit:read"]}
      }
    ]

    assert {:ok, report} = Security.report(%{"horizonDays" => "30"}, authorization)
    assert report["tenantScope"] == "current"
    assert is_map(report["securityEvents"])
    assert is_list(report["securityEvents"]["page"])
    assert {:ok, metrics} = Security.metrics(authorization)
    assert is_integer(metrics["loginFailures"])
  end

  test "security report rejects unsupported credential filters and invalid horizon" do
    authorization = [
      authorization: %{
        principal: %{data_scope: "ALL", permissions: ["audit:read"]}
      }
    ]

    assert {:error, :invalid_horizon} = Security.report(%{"horizonDays" => "91"}, authorization)

    assert {:error, :invalid_time} =
             Security.report(%{"from" => "not-an-instant"}, authorization)

    assert {:error, :unsupported_credential_filter} =
             Security.report(%{"credentialType" => "API_KEY"}, authorization)
  end
end
