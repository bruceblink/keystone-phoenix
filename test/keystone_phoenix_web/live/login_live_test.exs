defmodule KeystonePhoenixWeb.LoginLiveTest do
  use KeystonePhoenixWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  test "renders the login shell before authentication", %{conn: conn} do
    {:ok, view, html} = live(conn, "/")

    assert html =~ "管理后台正在迁移到 LiveView"
    assert has_element?(view, "#login-form")
    refute has_element?(view, "nav[aria-label='管理模块']")
  end
end
