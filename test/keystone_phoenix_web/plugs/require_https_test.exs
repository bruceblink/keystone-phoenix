defmodule KeystonePhoenixWeb.Plugs.RequireHttpsTest do
  use ExUnit.Case, async: false

  import Plug.Conn
  import Plug.Test

  alias KeystonePhoenixWeb.Plugs.RequireHttps

  setup do
    previous = Application.get_env(:keystone_phoenix, :force_ssl_enabled)
    previous_proxies = Application.get_env(:keystone_phoenix, :trusted_proxy_cidrs)

    on_exit(fn ->
      Application.put_env(:keystone_phoenix, :force_ssl_enabled, previous)
      Application.put_env(:keystone_phoenix, :trusted_proxy_cidrs, previous_proxies)
    end)

    :ok
  end

  test "rejects plain HTTP when production HTTPS is required" do
    Application.put_env(:keystone_phoenix, :force_ssl_enabled, true)
    Application.put_env(:keystone_phoenix, :trusted_proxy_cidrs, ["127.0.0.1/32"])

    conn = RequireHttps.call(conn(:get, "/api/v1/health"), [])

    assert conn.halted
    assert conn.status == 426
    assert get_resp_header(conn, "x-content-type-options") == ["nosniff"]
  end

  test "accepts HTTPS and trusted forwarded HTTPS" do
    Application.put_env(:keystone_phoenix, :force_ssl_enabled, true)
    Application.put_env(:keystone_phoenix, :trusted_proxy_cidrs, ["127.0.0.1/32"])

    https_conn = conn(:get, "/")
    https_conn = RequireHttps.call(%{https_conn | scheme: :https}, [])
    refute https_conn.halted

    forwarded = conn(:get, "/") |> put_req_header("x-forwarded-proto", "https, http")
    refute RequireHttps.call(forwarded, []).halted
  end

  test "does not trust forwarded HTTPS from an unregistered proxy" do
    Application.put_env(:keystone_phoenix, :force_ssl_enabled, true)
    Application.put_env(:keystone_phoenix, :trusted_proxy_cidrs, [])

    conn = conn(:get, "/") |> put_req_header("x-forwarded-proto", "https")
    assert RequireHttps.call(conn, []).halted
  end

  test "does not enforce HTTPS when local HTTP is explicitly allowed" do
    Application.put_env(:keystone_phoenix, :force_ssl_enabled, false)

    refute RequireHttps.call(conn(:get, "/"), []).halted
  end
end
