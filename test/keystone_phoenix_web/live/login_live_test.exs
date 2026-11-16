defmodule KeystonePhoenixWeb.LoginLiveTest do
  use KeystonePhoenixWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  test "renders the login shell before authentication", %{conn: conn} do
    {:ok, view, html} = live(conn, "/")

    assert html =~ "把平台状态"
    assert html =~ "<title>Keystone Admin</title>"
    assert html =~ ~s(href="/css/keystone.css")
    assert html =~ ~s(src="/js/live_socket.js")
    assert has_element?(view, ".login-intro .brand-mark svg")
    assert has_element?(view, ".login-card .brand-mark-small svg")
    assert has_element?(view, "#login-form")
    refute has_element?(view, "nav[aria-label='主导航']")
  end

  test "serves the extracted LiveView assets", %{conn: conn} do
    assert get(conn, "/css/keystone.css").status == 200
    assert get(conn, "/css/keystone-responsive.css").status == 200
    assert get(conn, "/css/admin-web-compat.css").resp_body =~ "@media (max-width: 850px)"
    assert get(conn, "/js/live_socket.js").status == 200
  end
end
