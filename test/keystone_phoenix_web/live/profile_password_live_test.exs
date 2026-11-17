defmodule KeystonePhoenixWeb.ProfilePasswordLiveTest do
  use KeystonePhoenixWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  import KeystonePhoenixWeb.LiveAuthenticationTestSupport,
    only: [create_user: 1, disable_captcha: 0, ensure_captcha_config: 0, live_socket: 1]

  alias KeystonePhoenix.Auth
  alias KeystonePhoenix.Authz.{PolicyCache, SysPermission, SysRolePermission}
  alias KeystonePhoenix.Repo
  alias KeystonePhoenix.Role.SysRole
  alias KeystonePhoenix.User.SysUser

  @password "Strong!123"
  @new_password "Changed!456"

  setup do
    ensure_captcha_config()
    disable_captcha()
    PolicyCache.invalidate()
    on_exit(&PolicyCache.invalidate/0)
    :ok
  end

  @tag :integration
  test "a permitted user can change a password when MFA is not required", %{conn: conn} do
    user = profile_user(true)
    view = login_profile(conn, user)

    {:ok, %{session_id: session_id}} =
      Auth.session_context(live_socket(view).assigns.access_token)

    render_submit(view, "change-profile-password", %{"password" => @new_password})

    assert render(view) =~ "密码已更新，请重新登录"
    updated = Repo.get!(SysUser, user.user_id)
    assert Bcrypt.verify_pass(@new_password, updated.password)
    refute Bcrypt.verify_pass(@password, updated.password)
    refute Auth.Session.active?(user.user_id, session_id)
  end

  @tag :integration
  test "profile policy rejects a weak password without changing credentials", %{conn: conn} do
    user = profile_user(true)
    view = login_profile(conn, user)
    original_hash = Repo.get!(SysUser, user.user_id).password

    {:ok, %{session_id: session_id}} =
      Auth.session_context(live_socket(view).assigns.access_token)

    render_submit(view, "change-profile-password", %{"password" => "test-only-disallowed"})

    assert has_element?(view, "#profile-feedback[role='alert']")
    assert render(view) =~ "密码不符合安全策略"
    assert Repo.get!(SysUser, user.user_id).password == original_hash
    assert Auth.Session.active?(user.user_id, session_id)
  end

  @tag :integration
  test "a user without password reset permission is rejected without changing the password", %{
    conn: conn
  } do
    user = profile_user(false)
    view = login_profile(conn, user)
    password_hash = Repo.get!(SysUser, user.user_id).password

    render_submit(view, "change-profile-password", %{"password" => @new_password})

    assert has_element?(view, "#profile-feedback[role='alert']", "没有操作权限")
    assert Repo.get!(SysUser, user.user_id).password == password_hash
    assert is_map(live_socket(view).assigns.current_user)
  end

  @tag :integration
  test "an MFA-required account cannot change its password before step-up", %{conn: conn} do
    user = profile_user(true)
    view = login_profile(conn, user)
    password_hash = Repo.get!(SysUser, user.user_id).password
    Repo.update!(Ecto.Changeset.change(user, mfa_required: true))

    render_submit(view, "change-profile-password", %{"password" => @new_password})

    assert has_element?(view, "#mfa-step-up-panel")
    assert render(view) =~ "修改密码需要完成二次认证"
    assert Repo.get!(SysUser, user.user_id).password == password_hash
    assert live_socket(view).assigns.mfa_step_up_required
  end

  defp login_profile(conn, user) do
    {:ok, view, _html} = live(conn, "/")
    render_submit(view, "login", %{"username" => user.username, "password" => @password})
    render_click(view, "show-panel", %{"panel" => "profile"})
    assert has_element?(view, "form[phx-submit='change-profile-password']")
    assert render(view) =~ "账号要求 MFA 时，更新密码前需完成二次验证。"
    view
  end

  defp profile_user(grant_reset_password?) do
    suffix = System.unique_integer([:positive])

    role =
      %SysRole{}
      |> SysRole.changeset(%{
        role_name: "个人改密测试角色 #{suffix}",
        role_key: "profile_password_#{suffix}",
        role_sort: 1,
        data_scope: "ALL",
        dept_id_set: "",
        status: 1
      })
      |> Repo.insert!()

    if grant_reset_password? do
      permission = Repo.get_by!(SysPermission, permission: "user:reset-password")

      Repo.insert!(%SysRolePermission{
        role_id: role.role_id,
        permission_id: permission.permission_id
      })
    end

    PolicyCache.invalidate()
    {:ok, user} = create_user(%{"role_id" => role.role_id})
    user
  end
end
