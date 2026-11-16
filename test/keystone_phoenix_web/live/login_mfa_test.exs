defmodule KeystonePhoenixWeb.LoginMfaTest do
  use KeystonePhoenixWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import KeystonePhoenixWeb.LiveAuthenticationTestSupport

  alias KeystonePhoenix.Auth
  alias KeystonePhoenix.Auth.Mfa
  alias KeystonePhoenix.Auth.Mfa.Totp
  alias KeystonePhoenix.Auth.Token

  @password "Strong!123"

  setup do
    ensure_captcha_config()
    disable_captcha()

    previous_key = Application.get_env(:keystone_phoenix, :mfa_master_key)
    previous_pepper = Application.get_env(:keystone_phoenix, :mfa_recovery_pepper)

    Application.put_env(
      :keystone_phoenix,
      :mfa_master_key,
      Base.encode64(:crypto.strong_rand_bytes(32))
    )

    Application.put_env(:keystone_phoenix, :mfa_recovery_pepper, "live-mfa-test-pepper")

    on_exit(fn ->
      Application.put_env(:keystone_phoenix, :mfa_master_key, previous_key)
      Application.put_env(:keystone_phoenix, :mfa_recovery_pepper, previous_pepper)
    end)

    :ok
  end

  test "password login displays and completes the LiveView MFA challenge", %{conn: conn} do
    {:ok, user} = create_user(%{})
    {secret, _initial} = enroll_mfa(user)
    assert {:ok, :ok} = Mfa.set_required(user.user_id, true)

    {:ok, view, _html} = live(conn, "/")

    render_submit(view, "login", %{"username" => user.username, "password" => @password})

    assert has_element?(view, "#mfa-login-form")
    assert has_element?(view, "#mfa-login-form .form-status[role='status']")
    assert has_element?(view, "#mfa-login-form label", "一次性验证码")
    assert has_element?(view, "#mfa-login-form .input-wrap #mfa-code")
    assert has_element?(view, "#mfa-login-form button.login-submit")
    assert has_element?(view, "#mfa-login-form button.button-ghost", "返回账号密码")
    refute has_element?(view, "nav[aria-label='主导航']")

    code = Totp.code(secret, System.system_time(:second) + Totp.step_seconds())
    render_submit(view, "verify-login-mfa", %{"code" => code})

    assert has_element?(view, "nav[aria-label='主导航']")

    assert {:ok, %{authentication_level: "AAL2"}} =
             Auth.session_context(live_socket(view).assigns.access_token)
  end

  test "MFA session conflict opens force-login confirmation and retries the challenge", %{
    conn: conn
  } do
    {:ok, user} = create_user(%{})
    {:ok, initial} = Auth.login_plaintext(user.username, @password, true)
    secret = enroll_mfa_with_session(user, initial)
    assert {:ok, :ok} = Mfa.set_required(user.user_id, true)

    {:ok, view, _html} = live(conn, "/")
    render_submit(view, "login", %{"username" => user.username, "password" => @password})

    code = Totp.code(secret, System.system_time(:second) + Totp.step_seconds())
    render_submit(view, "verify-login-mfa", %{"code" => code})

    assert has_element?(view, "section[role='dialog']", "账号已有活动会话")
    refute has_element?(view, "nav[aria-label='主导航']")

    render_click(view, "force-login")

    assert has_element?(view, "nav[aria-label='主导航']")
  end

  test "sensitive LiveView events require step-up before the handler runs", %{conn: conn} do
    role = create_admin_role()
    {:ok, admin} = create_user(%{"role_id" => role.role_id})
    {:ok, target} = create_user(%{})
    {secret, _initial} = enroll_mfa(admin)

    {:ok, view, _html} = live(conn, "/")
    render_submit(view, "login", %{"username" => admin.username, "password" => @password})

    render_submit(view, "reset-user-password", %{
      "userId" => to_string(target.user_id),
      "password" => "Changed!456"
    })

    assert has_element?(view, "#mfa-step-up-panel")
    assert render(view) =~ "需要完成二次认证"
    assert {:ok, before} = KeystonePhoenix.User.get_user(target.user_id)
    refute Bcrypt.verify_pass("Changed!456", before.password)

    render_click(view, "begin-liveview-step-up")
    assert has_element?(view, "#mfa-step-up-form")

    code = Totp.code(secret, System.system_time(:second) + Totp.step_seconds())
    render_submit(view, "verify-liveview-step-up", %{"code" => code})
    assert render(view) =~ "二次认证已完成"

    render_submit(view, "reset-user-password", %{
      "userId" => to_string(target.user_id),
      "password" => "Changed!456"
    })

    assert {:ok, updated} = KeystonePhoenix.User.get_user(target.user_id)
    assert Bcrypt.verify_pass("Changed!456", updated.password)
  end

  defp enroll_mfa(user) do
    {:ok, initial} = Auth.login_plaintext(user.username, @password, true)
    {:ok, claims} = Token.verify(initial.token, Token.access_type())

    {:ok, enrollment} =
      Mfa.begin_enrollment(user.user_id, user.username, claims["client_id"], claims["sid"])

    {:ok, _verification} =
      Mfa.verify_enrollment(
        user.user_id,
        enrollment.challenge_id,
        claims["client_id"],
        claims["sid"],
        Totp.code(enrollment.secret, System.system_time(:second))
      )

    Auth.logout(initial.refresh_token)
    {enrollment.secret, initial}
  end

  # 保留已有 AAL1 会话，验证 MFA 冲突时 challenge 可以在事务回滚后重试。
  defp enroll_mfa_with_session(user, initial) do
    {:ok, claims} = Token.verify(initial.token, Token.access_type())

    {:ok, enrollment} =
      Mfa.begin_enrollment(user.user_id, user.username, claims["client_id"], claims["sid"])

    {:ok, _verification} =
      Mfa.verify_enrollment(
        user.user_id,
        enrollment.challenge_id,
        claims["client_id"],
        claims["sid"],
        Totp.code(enrollment.secret, System.system_time(:second))
      )

    enrollment.secret
  end
end
