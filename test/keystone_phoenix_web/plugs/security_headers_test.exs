defmodule KeystonePhoenixWeb.Plugs.SecurityHeadersTest do
  use ExUnit.Case, async: false

  import Plug.Conn
  import Plug.Test

  alias KeystonePhoenixWeb.Plugs.SecurityHeaders

  setup do
    previous_origins = Application.get_env(:keystone_phoenix, :cors_allowed_origins)
    previous_force_ssl = Application.get_env(:keystone_phoenix, :force_ssl_enabled)

    on_exit(fn ->
      Application.put_env(:keystone_phoenix, :cors_allowed_origins, previous_origins)
      Application.put_env(:keystone_phoenix, :force_ssl_enabled, previous_force_ssl)
    end)

    :ok
  end

  test "adds baseline security headers to same-origin responses" do
    Application.put_env(:keystone_phoenix, :force_ssl_enabled, false)

    conn = apply_plug(conn(:get, "/"))

    assert get_resp_header(conn, "x-content-type-options") == ["nosniff"]
    assert get_resp_header(conn, "x-frame-options") == ["DENY"]
    assert get_resp_header(conn, "referrer-policy") == ["strict-origin-when-cross-origin"]

    assert get_resp_header(conn, "permissions-policy") == [
             "camera=(), geolocation=(), microphone=()"
           ]

    assert get_resp_header(conn, "content-security-policy") != []
    assert get_resp_header(conn, "strict-transport-security") == []
  end

  test "adds HSTS only when production HTTPS is enabled" do
    Application.put_env(:keystone_phoenix, :force_ssl_enabled, true)

    conn = apply_plug(conn(:get, "/"))

    assert get_resp_header(conn, "strict-transport-security") == [
             "max-age=31536000; includeSubDomains"
           ]
  end

  test "allows configured origins and handles preflight without credentials" do
    Application.put_env(:keystone_phoenix, :cors_allowed_origins, ["https://admin.example.com"])

    conn =
      conn(:options, "/api/v1/users")
      |> put_req_header("origin", "https://admin.example.com")
      |> apply_plug()

    assert conn.halted
    assert conn.status == 204
    assert conn.resp_body == ""
    assert get_resp_header(conn, "access-control-allow-origin") == ["https://admin.example.com"]

    assert get_resp_header(conn, "access-control-allow-methods") == [
             "GET,POST,PUT,PATCH,DELETE,OPTIONS"
           ]

    assert get_resp_header(conn, "access-control-allow-credentials") == []
  end

  test "does not grant CORS headers to an unconfigured origin" do
    Application.put_env(:keystone_phoenix, :cors_allowed_origins, ["https://admin.example.com"])

    conn =
      conn(:get, "/api/v1/users")
      |> put_req_header("origin", "https://attacker.example.com")
      |> apply_plug()

    refute conn.halted
    assert get_resp_header(conn, "access-control-allow-origin") == []
  end

  defp apply_plug(conn), do: SecurityHeaders.call(conn, SecurityHeaders.init([]))
end
