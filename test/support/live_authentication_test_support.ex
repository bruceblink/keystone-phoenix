defmodule KeystonePhoenixWeb.LiveAuthenticationTestSupport do
  @moduledoc """
  LiveView 认证测试共用的配置、数据夹具和会话断言。

  这些函数只服务于测试，集中处理验证码、UUID 主键和认证状态读取，避免认证场景文件重复定义基础逻辑。
  """

  import ExUnit.Assertions
  import Phoenix.LiveViewTest, only: [has_element?: 2, render: 1, render_submit: 3]

  @endpoint KeystonePhoenixWeb.Endpoint

  alias KeystonePhoenix.Authz.{SysPermission, SysRolePermission}
  alias KeystonePhoenix.Cache
  alias KeystonePhoenix.Config.SysConfig
  alias KeystonePhoenix.Department.SysDept
  alias KeystonePhoenix.Menu.SysMenu
  alias KeystonePhoenix.Repo
  alias KeystonePhoenix.Role.SysRole
  alias KeystonePhoenix.User.SysUser

  @captcha_config_key "sys.account.captchaOnOff"
  @captcha_prefix "keystone:auth:captcha:"
  @password "Strong!123"

  def login_view(conn, user) do
    {:ok, view, _html} = open_live(conn, "/")
    render_submit(view, "login", login_params(user))
    assert has_element?(view, "#login-form") == false
    {:ok, view, render(view)}
  end

  defp open_live(conn, path) do
    conn
    |> Phoenix.ConnTest.dispatch(@endpoint, :get, path)
    |> Phoenix.LiveViewTest.__live__(path, [])
  end

  def login_params(user, captcha_code \\ nil, captcha_key \\ nil) do
    params =
      if is_binary(captcha_code) do
        %{"username" => user.username, "password" => @password, "captchaCode" => captcha_code}
      else
        %{"username" => user.username, "password" => @password}
      end

    maybe_put_captcha_key(params, captcha_key)
  end

  def assert_expired(view, html) do
    assert html =~ "登录状态已失效，请重新登录"
    assert has_element?(view, "#login-form")
    refute has_element?(view, "nav[aria-label='管理模块']")
    assert authentication_cleared?(live_socket(view).assigns)
  end

  def authentication_cleared?(assigns) do
    is_nil(assigns.current_user) and is_nil(assigns.access_token) and
      is_nil(assigns.refresh_token) and assigns.permissions == [] and assigns.user_rows == [] and
      assigns.user_form == KeystonePhoenixWeb.Live.AdminSupport.empty_user_form()
  end

  def authenticated?(assigns),
    do: is_map(assigns.current_user) and is_binary(assigns.access_token)

  def enable_captcha, do: set_captcha("true")
  def disable_captcha, do: set_captcha("false")

  def set_captcha(value) do
    config = Repo.get_by!(SysConfig, config_key: @captcha_config_key, deleted: false)
    Repo.update!(Ecto.Changeset.change(config, config_value: value))
    clear_config_cache()
  end

  def clear_config_cache, do: Cache.delete_prefix("keystone:system:config:")

  def admin_principal(admin) do
    %{
      user_id: admin.user_id,
      role_id: admin.role_id,
      permissions: ["permission:manage", "user:update", "user:reset-password"]
    }
  end

  def ensure_captcha_config do
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

  def seed_captcha(view, answer, expires_at \\ nil) do
    key = live_socket(view).assigns.captcha_key
    expires_at = expires_at || System.monotonic_time(:millisecond) + 120_000

    :ets.insert(
      KeystonePhoenix.RuntimeStore.captcha_table(),
      {@captcha_prefix <> key, answer, expires_at}
    )

    key
  end

  def maybe_put_captcha_key(params, key) when is_binary(key),
    do: Map.put(params, "captchaCodeKey", key)

  def maybe_put_captcha_key(params, _key), do: params

  def live_socket(view), do: find_socket(:sys.get_state(view.pid))

  def find_socket(%Phoenix.LiveView.Socket{} = socket), do: socket
  def find_socket(%{} = map), do: map |> Map.values() |> Enum.find_value(&find_socket/1)

  def find_socket(tuple) when is_tuple(tuple),
    do: tuple |> Tuple.to_list() |> Enum.find_value(&find_socket/1)

  def find_socket(list) when is_list(list), do: Enum.find_value(list, &find_socket/1)
  def find_socket(_value), do: nil

  def create_user(attrs) do
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

    {:ok, user}
  end

  def create_admin_role do
    role =
      %SysRole{}
      |> SysRole.changeset(%{
        role_name: unique("Live 管理角色"),
        role_key: unique("live_admin_role"),
        role_sort: 1,
        data_scope: "ALL",
        dept_id_set: "",
        status: 1
      })
      |> Repo.insert!()

    for code <- ["permission:manage", "user:update", "user:reset-password"] do
      permission = Repo.get_by!(SysPermission, permission: code)

      Repo.insert!(%SysRolePermission{
        role_id: role.role_id,
        permission_id: permission.permission_id
      })
    end

    role
  end

  def create_scoped_user do
    {actor_dept, _target_dept} = insert_test_departments()

    role =
      %SysRole{}
      |> SysRole.changeset(%{
        role_name: unique("Live 认证角色"),
        role_key: unique("live_auth_role"),
        role_sort: 10,
        data_scope: "ALL",
        dept_id_set: "",
        status: 1
      })
      |> Repo.insert!()

    {:ok, user} = create_user(%{})

    user =
      Repo.update!(
        Ecto.Changeset.change(user, role_id: role.role_id, dept_id: actor_dept.dept_id)
      )

    {user, role}
  end

  def insert_test_departments do
    first =
      Repo.insert!(%SysDept{
        dept_id: KeystonePhoenix.Identity.v7(),
        parent_id: nil,
        ancestors: "",
        dept_name: unique("认证部门一"),
        status: 1
      })

    second =
      Repo.insert!(%SysDept{
        dept_id: KeystonePhoenix.Identity.v7(),
        parent_id: nil,
        ancestors: "",
        dept_name: unique("认证部门二"),
        status: 1
      })

    {first, second}
  end

  def create_menu(_permission) do
    %SysMenu{}
    |> SysMenu.changeset(%{
      menu_name: unique("Live 认证菜单"),
      menu_type: 1,
      router_name: "",
      parent_id: nil,
      path: "/live-auth",
      is_button: true,
      meta_info: "{}",
      status: 1,
      remark: ""
    })
    |> Repo.insert!()
  end

  def link_permission(role_id, menu, permission) do
    [resource, action] = String.split(permission, ":", parts: 2)

    entry =
      Repo.get_by(SysPermission, permission: permission) ||
        Repo.insert!(%SysPermission{
          permission: permission,
          resource: resource,
          domain: "default",
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

  def unique(prefix), do: "#{prefix}_#{System.unique_integer([:positive])}"
end
