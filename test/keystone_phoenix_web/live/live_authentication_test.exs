defmodule KeystonePhoenixWeb.LiveAuthenticationTest do
  use KeystonePhoenixWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias KeystonePhoenix.Auth.Captcha
  alias KeystonePhoenix.Auth
  alias KeystonePhoenix.Auth.Session
  alias KeystonePhoenix.Authz.{SysPermission, SysRolePermission}
  alias KeystonePhoenix.Config
  alias KeystonePhoenix.Config.SysConfig
  alias KeystonePhoenix.Department.SysDept
  alias KeystonePhoenix.Menu.SysMenu
  alias KeystonePhoenix.Repo
  alias KeystonePhoenix.Role.SysRole
  alias KeystonePhoenix.Role.SysRoleMenu
  alias KeystonePhoenix.User
  alias KeystonePhoenix.User.SysUser

  @captcha_config_key "sys.account.captchaOnOff"
  @captcha_prefix "keystone:auth:captcha:"
  @password "Strong!123"

  setup do
    ensure_captcha_config()
    Config.refresh_cache()
    on_exit(&Config.refresh_cache/0)

    {:ok, admin} =
      create_user(%{
        "username" => unique("live_auth_admin"),
        "nickname" => "认证管理员",
        "is_admin" => true
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
          principal: %{user_id: admin.user_id, is_admin: true},
          permission: "system:user:edit"
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
                 principal: %{user_id: admin.user_id, is_admin: true},
                 permission: "system:user:resetPwd"
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
             Repo.update(Ecto.Changeset.change(role, data_scope: 2, dept_id_set: "1"))

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
             Repo.update(Ecto.Changeset.change(role, dept_id_set: "1,2"))

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

    assert {:ok, _updated_user} = Repo.update(Ecto.Changeset.change(user, dept_id: 2))
    {:ok, before} = User.get_user(user.user_id)
    html = render_submit(view, "save-profile", %{"nickname" => "不应保存"})

    assert_expired(view, html)
    assert {:ok, after_user} = User.get_user(user.user_id)
    assert after_user.nickname == before.nickname
  end

  test "a changed role menu permission invalidates the session", %{conn: conn} do
    disable_captcha()
    {user, role} = create_scoped_user()
    first_menu = create_menu("system:user:list")
    Repo.insert!(%SysRoleMenu{role_id: role.role_id, menu_id: first_menu.menu_id})
    link_permission(role.role_id, first_menu, "system:user:list")
    {:ok, view, _html} = login_view(conn, user)

    second_permission = unique("system:profile:edit")
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
    assert {:ok, _updated_admin} = Repo.update(Ecto.Changeset.change(admin, is_admin: false))
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

  defp login_view(conn, user) do
    {:ok, view, _html} = live(conn, "/")
    render_submit(view, "login", login_params(user))
    assert has_element?(view, "#login-form") == false
    {:ok, view, render(view)}
  end

  defp login_params(user, captcha_code \\ nil, captcha_key \\ nil) do
    params =
      if is_binary(captcha_code) do
        %{"username" => user.username, "password" => @password, "captchaCode" => captcha_code}
      else
        %{"username" => user.username, "password" => @password}
      end

    maybe_put_captcha_key(params, captcha_key)
  end

  defp assert_expired(view, html) do
    assert html =~ "登录状态已失效，请重新登录"
    assert has_element?(view, "#login-form")
    refute has_element?(view, "nav[aria-label='管理模块']")
    assert authentication_cleared?(live_socket(view).assigns)
  end

  defp authentication_cleared?(assigns) do
    is_nil(assigns.current_user) and is_nil(assigns.access_token) and
      is_nil(assigns.refresh_token) and assigns.permissions == [] and assigns.user_rows == [] and
      assigns.user_form == KeystonePhoenixWeb.Live.AdminSupport.empty_user_form()
  end

  defp authenticated?(assigns),
    do: is_map(assigns.current_user) and is_binary(assigns.access_token)

  defp enable_captcha, do: set_captcha("true")
  defp disable_captcha, do: set_captcha("false")

  defp set_captcha(value) do
    config = Repo.get_by!(SysConfig, config_key: @captcha_config_key, deleted: false)
    Repo.update!(Ecto.Changeset.change(config, config_value: value))
    Config.refresh_cache()
  end

  defp ensure_captcha_config do
    case Repo.get_by(SysConfig, config_key: @captcha_config_key, deleted: false) do
      nil ->
        SysConfig.changeset(%SysConfig{}, %{
          config_name: "账号自助-验证码开关",
          config_key: @captcha_config_key,
          config_options: Jason.encode!(["true", "false"]),
          config_value: "false",
          is_allow_change: false,
          remark: "LiveView authentication test"
        })
        |> Repo.insert!()

      config ->
        config
    end
  end

  defp seed_captcha(view, answer, expires_at \\ nil) do
    key = live_socket(view).assigns.captcha_key
    expires_at = expires_at || System.monotonic_time(:millisecond) + 120_000

    :ets.insert(
      KeystonePhoenix.RuntimeStore.captcha_table(),
      {@captcha_prefix <> key, answer, expires_at}
    )

    key
  end

  defp maybe_put_captcha_key(params, key) when is_binary(key),
    do: Map.put(params, "captchaCodeKey", key)

  defp maybe_put_captcha_key(params, _key), do: params

  defp live_socket(view), do: find_socket(:sys.get_state(view.pid))

  defp find_socket(%Phoenix.LiveView.Socket{} = socket), do: socket
  defp find_socket(%{} = map), do: map |> Map.values() |> Enum.find_value(&find_socket/1)

  defp find_socket(tuple) when is_tuple(tuple),
    do: tuple |> Tuple.to_list() |> Enum.find_value(&find_socket/1)

  defp find_socket(list) when is_list(list), do: Enum.find_value(list, &find_socket/1)
  defp find_socket(_value), do: nil

  defp create_user(attrs) do
    attrs =
      Map.merge(
        %{
          "username" => unique("live_auth_user"),
          "nickname" => "Live 认证用户",
          "password" => @password,
          "status" => 1
        },
        attrs
      )

    user =
      %SysUser{}
      |> SysUser.create_changeset(attrs)
      |> Repo.insert!()

    if Map.get(attrs, "is_admin", false) do
      {:ok, Repo.update!(Ecto.Changeset.change(user, is_admin: true))}
    else
      {:ok, user}
    end
  end

  defp create_scoped_user do
    insert_test_departments()

    role =
      %SysRole{}
      |> SysRole.changeset(%{
        role_name: unique("Live 认证角色"),
        role_key: unique("live_auth_role"),
        role_sort: 10,
        data_scope: 1,
        dept_id_set: "",
        status: 1
      })
      |> Repo.insert!()

    {:ok, user} = create_user(%{})

    user = Repo.update!(Ecto.Changeset.change(user, role_id: role.role_id, dept_id: 1))
    {user, role}
  end

  defp insert_test_departments do
    Repo.insert!(%SysDept{
      dept_id: 1,
      parent_id: 0,
      ancestors: "0",
      dept_name: unique("认证部门一"),
      status: 1
    })

    Repo.insert!(%SysDept{
      dept_id: 2,
      parent_id: 0,
      ancestors: "0",
      dept_name: unique("认证部门二"),
      status: 1
    })
  end

  defp create_menu(_permission) do
    %SysMenu{}
    |> SysMenu.changeset(%{
      menu_name: unique("Live 认证菜单"),
      menu_type: 1,
      router_name: "",
      parent_id: 0,
      path: "/live-auth",
      is_button: true,
      meta_info: "{}",
      status: 1,
      remark: ""
    })
    |> Repo.insert!()
  end

  defp link_permission(role_id, menu, permission) do
    [resource, domain, action] = String.split(permission, ":", parts: 3)

    entry =
      Repo.get_by(SysPermission, permission: permission) ||
        Repo.insert!(%SysPermission{
          permission: permission,
          resource: resource,
          domain: domain,
          action: action,
          status: 1,
          deprecated: false
        })

    Repo.insert!(%SysRolePermission{role_id: role_id, permission_id: entry.permission_id})

    Repo.insert!(%KeystonePhoenix.Authz.SysMenuPermission{
      menu_id: menu.menu_id,
      permission_id: entry.permission_id
    })
  end

  defp unique(prefix), do: "#{prefix}_#{System.unique_integer([:positive])}"
end
