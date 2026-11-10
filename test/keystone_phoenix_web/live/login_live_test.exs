defmodule KeystonePhoenixWeb.LoginLiveTest do
  use KeystonePhoenixWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  test "renders the login shell before authentication", %{conn: conn} do
    {:ok, view, html} = live(conn, "/")

    assert html =~ "管理后台正在迁移到 LiveView"
    assert html =~ ~s(href="/css/keystone.css")
    assert html =~ ~s(src="/js/live_socket.js")
    assert has_element?(view, "#login-form")
    refute has_element?(view, "nav[aria-label='管理模块']")
  end

  test "serves the extracted LiveView assets", %{conn: conn} do
    assert get(conn, "/css/keystone.css").status == 200
    assert get(conn, "/js/live_socket.js").status == 200
  end
end
