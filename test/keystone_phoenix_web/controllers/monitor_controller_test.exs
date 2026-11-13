defmodule KeystonePhoenixWeb.MonitorControllerTest do
  use KeystonePhoenixWeb.ConnCase, async: false

  test "network status stream requires monitor server permission", %{conn: conn} do
    response = get(conn, "/monitor/networkStatus/stream")

    assert response.status == 401
    assert get_in(json_response(response, 401), ["error", "code"]) == "session_revoked"
  end
end
