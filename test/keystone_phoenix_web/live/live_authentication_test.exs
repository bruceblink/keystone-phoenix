defmodule KeystonePhoenixWeb.LiveAuthenticationTest do
  use KeystonePhoenixWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import KeystonePhoenixWeb.LiveAuthenticationTestSupport

  alias KeystonePhoenix.Auth.Captcha
  alias KeystonePhoenix.Auth
  alias KeystonePhoenix.Auth.Session
  alias KeystonePhoenix.Repo
  alias KeystonePhoenix.Role.SysRoleMenu
  alias KeystonePhoenix.User

  @password "Strong!123"

  setup do
    ensure_captcha_config()
    clear_config_cache()
    on_exit(&clear_config_cache/0)

    admin_role = create_admin_role()

    {:ok, admin} =
      create_user(%{
        "username" => unique("live_auth_admin"),
        "nickname" => "认证管理员",
        "role_id" => admin_role.role_id
      })

    {:ok, admin: admin}
  end

  test "first login succeeds and a second connection keeps the first session", %{
    conn: conn,
    admin: admin
  } do
    disable_captcha()
    {:ok, first, _html} = live(conn, "/")

    render_submit(first, "login", login_params(admin))
    assert has_element?(first, "nav[aria-label='管理模块']")

    {:ok, second, _html} = live(conn, "/")
    html = render_submit(second, "login", login_params(admin))

    assert html =~ "该账号已经登录"
    assert has_element?(first, "nav[aria-label='管理模块']")
    assert has_element?(second, "#login-form")
  end

  test "captcha rejects a missing code, an invalid code, and an expired code", %{
    conn: conn,
    admin: admin
  } do
    enable_captcha()

    {:ok, missing_view, _html} = live(conn, "/")
    missing_html = render_submit(missing_view, "login", login_params(admin))
    assert missing_html =~ "请输入验证码"
    refute has_element?(missing_view, "nav[aria-label='管理模块']")

    {:ok, invalid_view, _html} = live(conn, "/")
    seed_captcha(invalid_view, "7")
    invalid_html = render_submit(invalid_view, "login", login_params(admin, "wrong"))
    assert invalid_html =~ "验证码错误，请重试"
    refute has_element?(invalid_view, "nav[aria-label='管理模块']")

    {:ok, expired_view, _html} = live(conn, "/")
    seed_captcha(expired_view, "7", System.monotonic_time(:millisecond) - 1)
    expired_html = render_submit(expired_view, "login", login_params(admin, "7"))
    assert expired_html =~ "验证码已过期，请重试"
    refute has_element?(expired_view, "nav[aria-label='管理模块']")
  end

  test "a successful login consumes the captcha exactly once", %{conn: conn, admin: admin} do
    enable_captcha()
    {:ok, view, _html} = live(conn, "/")
    key = seed_captcha(view, "7")

    render_submit(view, "login", login_params(admin, "7"))

    assert has_element?(view, "nav[aria-label='管理模块']")
    assert {:error, :captcha_expired} = Captcha.validate("7", key)
  end

  test "client captcha keys cannot replace the refreshed connection key", %{
    conn: conn,
    admin: admin
  } do
    enable_captcha()
    {:ok, view, _html} = live(conn, "/")
    old_key = seed_captcha(view, "7")

    render_click(view, "refresh-captcha")
    new_key = seed_captcha(view, "8")

    unless old_key != new_key, do: flunk("captcha key did not rotate")

    html = render_submit(view, "login", login_params(admin, "7", old_key))

    assert html =~ "验证码错误，请重试"
    refute has_element?(view, "nav[aria-label='管理模块']")
    assert :ok = Captcha.validate("7", old_key)
  end

  test "a consumed captcha cannot be replayed through the login event", %{
    conn: conn,
    admin: admin
  } do
    enable_captcha()
    {:ok, view, _html} = live(conn, "/")
    old_key = seed_captcha(view, "7")

    assert :ok = Captcha.validate("7", old_key)
    html = render_submit(view, "login", login_params(admin, "7"))

    assert html =~ "验证码已过期，请重试"
    refute has_element?(view, "nav[aria-label='管理模块']")
  end

  test "a normal profile update leaves the session valid for later events", %{conn: conn} do
    disable_captcha()
    {:ok, user} = create_user(%{"nickname" => "初始昵称"})
    {:ok, view, _html} = login_view(conn, user)
    render_click(view, "show-panel", %{"panel" => "profile"})

    render_submit(view, "save-profile", %{"nickname" => "第一次更新"})
    assert render(view) =~ "个人资料已保存"

    render_submit(view, "save-profile", %{"email" => "second@example.com"})

    assert authenticated?(live_socket(view).assigns)
    refute render(view) =~ "登录状态已失效，请重新登录"
    assert {:ok, updated} = User.get_user(user.user_id)
    assert updated.nickname == "第一次更新"
    assert updated.email == "second@example.com"
  end

  test "revoked sessions cannot submit a profile event", %{conn: conn, admin: admin} do
    disable_captcha()
    {:ok, view, _html} = login_view(conn, admin)
    {:ok, before} = User.get_user(admin.user_id)

    assert :ok = Session.revoke_account(admin.user_id)
    html = render_submit(view, "save-profile", %{"nickname" => "不应保存"})

    assert_expired(view, html)
    assert {:ok, after_user} = User.get_user(admin.user_id)
    assert after_user.nickname == before.nickname
  end

  test "a disabled account cannot submit a profile event", %{conn: conn, admin: admin} do
    disable_captcha()
    {:ok, view, _html} = login_view(conn, admin)

    {:ok, _disabled} =
      User.change_status(admin.user_id, 0,
        authorization: %{
          principal: admin_principal(admin),
          permission: "user:update"
        }
      )

    {:ok, before} = User.get_user(admin.user_id)

    html = render_submit(view, "save-profile", %{"nickname" => "不应保存"})

    assert_expired(view, html)
    assert {:ok, after_user} = User.get_user(admin.user_id)
    assert after_user.nickname == before.nickname
  end

  test "a password reset invalidates an existing LiveView session", %{conn: conn, admin: admin} do
    disable_captcha()
    {:ok, view, _html} = login_view(conn, admin)

    assert {:ok, _reset} =
             User.reset_password(admin.user_id, %{"password" => "Reset!456"},
               authorization: %{
                 principal: admin_principal(admin),
                 permission: "user:reset-password"
               }
             )

    {:ok, before} = User.get_user(admin.user_id)

    html = render_submit(view, "save-profile", %{"nickname" => "不应保存"})

    assert_expired(view, html)
    assert {:ok, after_user} = User.get_user(admin.user_id)
    assert after_user.nickname == before.nickname
  end

  test "a role data-scope change invalidates the session", %{conn: conn} do
    disable_captcha()
    {user, role} = create_scoped_user()
    {:ok, view, _html} = login_view(conn, user)

    assert {:ok, _role} =
             Repo.update(
               Ecto.Changeset.change(role, data_scope: "CUSTOM", dept_id_set: user.dept_id)
             )

    {:ok, before} = User.get_user(user.user_id)
    html = render_submit(view, "save-profile", %{"nickname" => "不应保存"})

    assert_expired(view, html)
    assert {:ok, after_user} = User.get_user(user.user_id)
    assert after_user.nickname == before.nickname
  end

  test "a role department-set change invalidates the session", %{conn: conn} do
    disable_captcha()
    {user, role} = create_scoped_user()
    {:ok, view, _html} = login_view(conn, user)

    assert {:ok, _role} =
             Repo.update(
               Ecto.Changeset.change(role,
                 dept_id_set: Enum.join([user.dept_id, user.dept_id], ",")
               )
             )

    {:ok, before} = User.get_user(user.user_id)
    html = render_submit(view, "save-profile", %{"nickname" => "不应保存"})

    assert_expired(view, html)
    assert {:ok, after_user} = User.get_user(user.user_id)
    assert after_user.nickname == before.nickname
  end

  test "a role-key change invalidates the session", %{conn: conn} do
    disable_captcha()
    {user, role} = create_scoped_user()
    {:ok, view, _html} = login_view(conn, user)

    assert {:ok, _role} =
             Repo.update(Ecto.Changeset.change(role, role_key: role.role_key <> "_changed"))

    {:ok, before} = User.get_user(user.user_id)
    html = render_submit(view, "save-profile", %{"nickname" => "不应保存"})

    assert_expired(view, html)
    assert {:ok, after_user} = User.get_user(user.user_id)
    assert after_user.nickname == before.nickname
  end

  test "an account department change invalidates the session", %{conn: conn} do
    disable_captcha()
    {user, _role} = create_scoped_user()
    {:ok, view, _html} = login_view(conn, user)

    assert {:ok, _updated_user} = Repo.update(Ecto.Changeset.change(user, dept_id: nil))
    {:ok, before} = User.get_user(user.user_id)
    html = render_submit(view, "save-profile", %{"nickname" => "不应保存"})

    assert_expired(view, html)
    assert {:ok, after_user} = User.get_user(user.user_id)
    assert after_user.nickname == before.nickname
  end

  test "a changed role menu permission invalidates the session", %{conn: conn} do
    disable_captcha()
    {user, role} = create_scoped_user()
    first_menu = create_menu("user:read")
    Repo.insert!(%SysRoleMenu{role_id: role.role_id, menu_id: first_menu.menu_id})
    link_permission(role.role_id, first_menu, "user:read")
    {:ok, view, _html} = login_view(conn, user)

    second_permission = "menu:read"
    second_menu = create_menu(second_permission)
    Repo.insert!(%SysRoleMenu{role_id: role.role_id, menu_id: second_menu.menu_id})
    link_permission(role.role_id, second_menu, second_permission)
    {:ok, before} = User.get_user(user.user_id)
    html = render_submit(view, "save-profile", %{"nickname" => "不应保存"})

    assert_expired(view, html)
    assert {:ok, after_user} = User.get_user(user.user_id)
    assert after_user.nickname == before.nickname
  end

  test "admin privilege removal blocks a management write", %{conn: conn, admin: admin} do
    disable_captcha()
    {:ok, target} = create_user(%{"nickname" => "目标用户"})
    {:ok, view, _html} = login_view(conn, admin)
    assert {:ok, _updated_admin} = Repo.update(Ecto.Changeset.change(admin, role_id: nil))
    {:ok, before} = User.get_user(target.user_id)

    html =
      render_submit(view, "save-user", %{
        "userId" => to_string(target.user_id),
        "username" => target.username,
        "nickname" => "不应保存"
      })

    assert_expired(view, html)
    assert {:ok, after_user} = User.get_user(target.user_id)
    assert after_user.nickname == before.nickname
  end

  test "forced login invalidates the previous view before a management write", %{
    conn: conn,
    admin: admin
  } do
    disable_captcha()
    {:ok, target} = create_user(%{"nickname" => "目标用户"})
    {:ok, view, _html} = login_view(conn, admin)

    assert elem(Auth.login_plaintext(admin.username, @password, true), 0) == :ok
    {:ok, before} = User.get_user(target.user_id)

    html =
      render_submit(view, "save-user", %{
        "userId" => to_string(target.user_id),
        "username" => target.username,
        "nickname" => "不应保存"
      })

    assert_expired(view, html)
    assert {:ok, after_user} = User.get_user(target.user_id)
    assert after_user.nickname == before.nickname
  end

  test "an expired access token requires login again", %{conn: conn, admin: admin} do
    disable_captcha()
    previous_ttl = Application.get_env(:keystone_phoenix, :jwt_access_ttl)
    Application.put_env(:keystone_phoenix, :jwt_access_ttl, -1)

    on_exit(fn ->
      Application.put_env(:keystone_phoenix, :jwt_access_ttl, previous_ttl)
    end)

    {:ok, view, _html} = login_view(conn, admin)
    {:ok, before} = User.get_user(admin.user_id)
    html = render_submit(view, "save-profile", %{"nickname" => "不应保存"})

    assert_expired(view, html)
    assert {:ok, after_user} = User.get_user(admin.user_id)
    assert after_user.nickname == before.nickname
  end

  test "handle_info is also rejected after the session is revoked", %{conn: conn, admin: admin} do
    disable_captcha()
    {:ok, view, _html} = login_view(conn, admin)
    assert :ok = Session.revoke_account(admin.user_id)

    send(view.pid, {:admin_job_finished, 0, :ok})
    html = render(view)

    assert_expired(view, html)
  end

  test "Phoenix logger filters credentials, tokens, secrets, and captcha fields recursively" do
    values = %{
      "username" => "visible",
      "password" => "hidden",
      "oldPassword" => "hidden",
      "newPassword" => "hidden",
      "refreshToken" => "hidden",
      "captchaCode" => "hidden",
      "captchaCodeKey" => "hidden",
      "nested" => [%{"password" => "hidden", "username" => "visible"}]
    }

    filtered = Phoenix.Logger.filter_values(values)

    assert filtered["username"] == "visible"
    assert filtered["nested"] == [%{"password" => "[FILTERED]", "username" => "visible"}]

    for key <- ~w(password oldPassword newPassword refreshToken captchaCode captchaCodeKey) do
      assert filtered[key] == "[FILTERED]"
    end
  end
end
