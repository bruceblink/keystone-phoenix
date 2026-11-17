defmodule KeystonePhoenixWeb.LoginInitialPasswordTest do
  use KeystonePhoenixWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  import KeystonePhoenixWeb.LiveAuthenticationTestSupport,
    only: [create_user: 1, disable_captcha: 0, ensure_captcha_config: 0, live_socket: 1]

  alias KeystonePhoenix.Auth
  alias KeystonePhoenix.Repo

  @current_password "Strong!123"
  @new_password "Changed!456"

  setup do
    ensure_captcha_config()
    disable_captcha()
    {:ok, user} = create_user(%{})
    user = Repo.update!(Ecto.Changeset.change(user, must_change_password: true))

    {:ok, user: user}
  end

  @tag :integration
  test "requires initial password change and keeps submitted passwords out of socket assigns", %{
    conn: conn,
    user: user
  } do
    {:ok, view, _html} = live(conn, "/")

    render_submit(view, "login", %{
      "username" => user.username,
      "password" => @current_password
    })

    assert has_element?(view, "#initial-password-form")
    assert has_element?(view, "#initial-password-fields[phx-update='ignore']")
    assert has_element?(view, ".login-card h2", "设置新密码")
    assert has_element?(view, ".initial-password-panel", "账号：#{user.username}")
    refute has_element?(view, "nav[aria-label='主导航']")
    assert live_socket(view).assigns.initial_password_required
    assert live_socket(view).assigns.password == ""

    render_submit(view, "change-initial-password", %{
      "currentPassword" => "incorrect-current-password",
      "newPassword" => @new_password,
      "confirmPassword" => "Different!789"
    })

    assert has_element?(view, ".initial-password-panel [role='alert']", "两次输入的新密码不一致")

    render_submit(view, "change-initial-password", %{
      "currentPassword" => "incorrect-current-password",
      "newPassword" => @new_password,
      "confirmPassword" => @new_password
    })

    assert has_element?(view, ".initial-password-panel [role='alert']", "当前密码不正确")
    assert Repo.get!(KeystonePhoenix.User.SysUser, user.user_id).must_change_password

    render_submit(view, "change-initial-password", %{
      "currentPassword" => @current_password,
      "newPassword" => "weak",
      "confirmPassword" => "weak"
    })

    assert has_element?(view, ".initial-password-panel [role='alert']", "新密码不符合系统密码要求")
    assert Repo.get!(KeystonePhoenix.User.SysUser, user.user_id).must_change_password

    render_submit(view, "change-initial-password", %{
      "currentPassword" => @current_password,
      "newPassword" => @new_password,
      "confirmPassword" => @new_password
    })

    html = render(view)
    assert html =~ "密码已更新，请使用新密码登录"
    assert has_element?(view, "#login-form")
    refute has_element?(view, "#initial-password-form")
    refute html =~ @current_password
    refute html =~ @new_password
    refute inspect(live_socket(view).assigns) =~ @current_password
    refute inspect(live_socket(view).assigns) =~ @new_password
    refute Repo.get!(KeystonePhoenix.User.SysUser, user.user_id).must_change_password

    assert {:ok, tokens} = Auth.login_plaintext(user.username, @new_password)
    Auth.logout(tokens.refresh_token)
  end

  @tag :integration
  test "cancel returns to the normal login form", %{conn: conn, user: user} do
    {:ok, view, _html} = live(conn, "/")

    render_submit(view, "login", %{
      "username" => user.username,
      "password" => @current_password
    })

    assert has_element?(view, "#initial-password-form")
    render_click(view, "cancel-initial-password")

    assert has_element?(view, "#login-form")
    refute has_element?(view, "#initial-password-form")
    assert live_socket(view).assigns.initial_password_required == false
  end
end
