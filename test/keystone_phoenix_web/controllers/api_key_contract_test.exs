defmodule KeystonePhoenixWeb.ApiKeyContractTest do
  use KeystonePhoenixWeb.ConnCase, async: false

  test "API Key management uses the versioned resource path", %{conn: conn} do
    response = post(conn, "/api/v1/api-keys", %{"name" => "worker", "scopes" => ["api-key:read"]})

    assert response.status == 401
    assert get_in(json_response(response, 401), ["error", "code"]) == "session_revoked"
  end

  test "unversioned API Key paths are unavailable" do
    assert post(build_conn(), "/api-keys", %{}).status == 404
    assert get(build_conn(), "/api/v1/api-keys").status == 401
  end
end
