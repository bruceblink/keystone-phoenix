defmodule KeystonePhoenixWeb.LoginConfirmationTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias KeystonePhoenixWeb.Live.AdminPages.LoginConfirmation

  test "renders cancel and force login actions" do
    html = render_component(&LoginConfirmation.modal/1, %{open: true})

    assert html =~ "账号已有活动会话"
    assert html =~ ~s(phx-click="cancel-force-login")
    assert html =~ ~s(phx-click="force-login")
    assert html =~ "强制登录会使该账号的其他活动会话失效"
  end
end
