defmodule KeystonePhoenixWeb.ReadonlyPanelsTest do
  use KeystonePhoenixWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias KeystonePhoenix.Cache
  alias KeystonePhoenix.Authz.{SysPermission, SysRolePermission}
  alias KeystonePhoenix.Config.SysConfig
  alias KeystonePhoenix.Dictionary.DictData
  alias KeystonePhoenix.Dictionary.DictType
  alias KeystonePhoenix.Log
  alias KeystonePhoenix.Menu.SysMenu
  alias KeystonePhoenix.Repo
  alias KeystonePhoenix.Role.{SysRole, SysRoleMenu}
  alias KeystonePhoenix.User.SysUser
  alias KeystonePhoenix.Department.SysDept
  alias KeystonePhoenix.Identity

  @password "Strong!123"
  @captcha_config_key "sys.account.captchaOnOff"

  setup do
    ensure_captcha_disabled()
    clear_config_cache()
    on_exit(&clear_config_cache/0)
    :ok
  end

  test "an ordinary user can open profile and overview", %{conn: conn} do
    user = create_user()
    {:ok, view, _html} = login_view(conn, user)

    render_click(view, "show-panel", %{"panel" => "profile"})
    assert live_socket(view).assigns.active_panel == "profile"
    assert has_element?(view, "form[phx-submit='save-profile']")

    render_click(view, "show-panel", %{"panel" => "overview"})
    assert live_socket(view).assigns.active_panel == "overview"
    assert render(view) =~ "当前登录用户"
  end

  test "a read-only user refreshes users and remains data scoped", %{conn: conn} do
    parent = insert_dept("父部门")
    outside = insert_dept("外部部门")

    role =
      insert_role(%{
        data_scope: "DEPARTMENT",
        permission: "user:read"
      })

    actor = create_user(%{role_id: role.role_id, dept_id: parent.dept_id})
    same_dept = create_user(%{dept_id: parent.dept_id})
    outside_dept = create_user(%{dept_id: outside.dept_id})
    {:ok, view, _html} = login_view(conn, actor)

    user_ids = Enum.map(live_socket(view).assigns.user_rows, & &1["userId"])
    assert actor.user_id in user_ids
    assert same_dept.user_id in user_ids
    refute outside_dept.user_id in user_ids

    inserted_after_login = create_user(%{dept_id: parent.dept_id})

    assert inserted_after_login.user_id not in Enum.map(
             live_socket(view).assigns.user_rows,
             & &1["userId"]
           )

    render_click(view, "show-panel", %{"panel" => "users"})
    assert has_element?(view, "button[phx-click='refresh-users']")
    refute has_element?(view, "form[phx-submit='save-user']")

    render_click(view, "refresh-users")
    refreshed_ids = Enum.map(live_socket(view).assigns.user_rows, & &1["userId"])
    assert inserted_after_login.user_id in refreshed_ids
    refute outside_dept.user_id in refreshed_ids
  end

  test "a scoped user cannot load global role data through LiveView", %{conn: conn} do
    role = insert_role(%{data_scope: "DEPARTMENT", permission: "role:read"})
    user = create_user(%{role_id: role.role_id})
    {:ok, view, _html} = login_view(conn, user)

    assert live_socket(view).assigns.role_rows == []
    refute live_socket(view).assigns.panel_access["roles"]

    render_click(view, "show-panel", %{"panel" => "roles"})
    assert live_socket(view).assigns.active_panel == "overview"
  end

  test "an ordinary user without list permission cannot select or refresh panels", %{conn: conn} do
    user = create_user()
    {:ok, view, _html} = login_view(conn, user)

    render_click(view, "show-panel", %{"panel" => "users"})
    assert live_socket(view).assigns.active_panel == "overview"
    assert live_socket(view).assigns.user_rows == []

    render_click(view, "refresh-users")
    assert live_socket(view).assigns.user_rows == []

    insert_dict_fixture()
    render_click(view, "select-dict-type", %{"dict-type" => "readonly.type"})
    assert live_socket(view).assigns.selected_dict_type == ""
    assert live_socket(view).assigns.dict_data_rows == []

    render_click(view, "refresh-monitor")
    assigns = live_socket(view).assigns
    assert assigns.monitor_server_info == %{}
    assert assigns.monitor_cache_info == %{}
    assert assigns.online_user_rows == []
    assert assigns.network_status == %{}
    assert assigns.security_access == false
    assert assigns.security_api_keys == %{}
    assert assigns.security_event_rows == []
  end

  test "a read-only user cannot submit a management write", %{conn: conn} do
    role = insert_role(%{permission: "user:read"})
    user = create_user(%{role_id: role.role_id})
    target = create_user()
    {:ok, view, _html} = login_view(conn, user)

    render_click(view, "show-panel", %{"panel" => "users"})
    before = Repo.get!(SysUser, target.user_id)

    render_submit(view, "save-user", %{
      "userId" => to_string(target.user_id),
      "username" => target.username,
      "nickname" => "不应保存"
    })

    assert Repo.get!(SysUser, target.user_id).nickname == before.nickname
    refute render(view) =~ "用户已更新"
  end

  test "login and operation log refresh permissions stay separate", %{conn: conn} do
    login_role = insert_role(%{permission: "login-log:read"})
    operation_role = insert_role(%{permission: "operation-log:read"})
    login_user = create_user(%{role_id: login_role.role_id})
    operation_user = create_user(%{role_id: operation_role.role_id})

    {:ok, login_view, _html} = login_view(conn, login_user)
    render_click(login_view, "show-panel", %{"panel" => "logs"})
    render_click(login_view, "refresh-logs")
    login_assigns = live_socket(login_view).assigns
    assert login_assigns.login_log_rows != []
    assert login_assigns.operation_log_rows == []

    assert {:ok, _log} =
             Log.create_operation_log(
               %{"requestModule" => "readonly-test"},
               operation_user,
               "/readonly-test",
               "GET"
             )

    {:ok, operation_view, _html} = login_view(conn, operation_user)
    render_click(operation_view, "show-panel", %{"panel" => "logs"})
    render_click(operation_view, "refresh-logs")
    operation_assigns = live_socket(operation_view).assigns
    assert operation_assigns.login_log_rows == []

    assert Enum.any?(
             operation_assigns.operation_log_rows,
             &(&1["requestModule"] == "readonly-test")
           )
  end

  test "a dictionary reader can select data, while an unprivileged user cannot", %{conn: conn} do
    insert_dict_fixture()
    role = insert_role(%{permission: "dictionary:read"})
    reader = create_user(%{role_id: role.role_id})
    {:ok, reader_view, _html} = login_view(conn, reader)

    assert live_socket(reader_view).assigns.dict_type_rows != []
    render_click(reader_view, "show-panel", %{"panel" => "dicts"})
    render_click(reader_view, "select-dict-type", %{"dict-type" => "readonly.type"})
    assert live_socket(reader_view).assigns.selected_dict_type == "readonly.type"
    assert Enum.any?(live_socket(reader_view).assigns.dict_data_rows, &(&1["dictLabel"] == "只读值"))

    unprivileged = create_user()
    {:ok, unprivileged_view, _html} = login_view(conn, unprivileged)
    render_click(unprivileged_view, "select-dict-type", %{"dict-type" => "readonly.type"})
    assert live_socket(unprivileged_view).assigns.selected_dict_type == ""
    assert live_socket(unprivileged_view).assigns.dict_data_rows == []
  end

  test "monitor permissions load only their own metric", %{conn: conn} do
    server_user = create_monitor_user("server:read")
    cache_user = create_monitor_user("cache:refresh")
    online_user = create_monitor_user("online-session:read")

    {:ok, server_view, _html} = login_view(conn, server_user)
    render_click(server_view, "show-panel", %{"panel" => "monitor"})
    server = live_socket(server_view).assigns
    assert server.monitor_server_info != %{}
    assert server.network_status != %{}
    assert server.monitor_cache_info == %{}
    assert server.online_user_rows == []

    {:ok, cache_view, _html} = login_view(conn, cache_user)
    render_click(cache_view, "show-panel", %{"panel" => "monitor"})
    cache = live_socket(cache_view).assigns
    assert cache.monitor_cache_info != %{}
    assert cache.monitor_server_info == %{}
    assert cache.online_user_rows == []
    assert cache.network_status == %{}

    {:ok, online_view, _html} = login_view(conn, online_user)
    render_click(online_view, "show-panel", %{"panel" => "monitor"})
    online = live_socket(online_view).assigns
    assert online.online_user_rows != []
    assert online.monitor_server_info == %{}
    assert online.monitor_cache_info == %{}
    assert online.network_status == %{}
  end

  test "audit readers see the redacted security report in the monitor panel", %{conn: conn} do
    audit_user = create_monitor_user("audit:read")
    {:ok, view, _html} = login_view(conn, audit_user)

    render_click(view, "show-panel", %{"panel" => "monitor"})
    assigns = live_socket(view).assigns

    assert assigns.security_access
    assert is_integer(assigns.security_metrics["loginFailures"])
    assert assigns.security_api_keys["rotated"] == 0
    assert is_integer(assigns.security_event_total)
    assert render(view) =~ "安全运营报告"
    assert render(view) =~ "安全运营指标"
  end

  test "administrator can issue, rotate, filter, and revoke API Keys", %{conn: conn} do
    admin_role = Repo.get_by!(SysRole, role_key: "admin")
    admin = create_user(%{role_id: admin_role.role_id})
    {:ok, view, _html} = login_view(conn, admin)

    render_click(view, "show-panel", %{"panel" => "api-keys"})
    assert has_element?(view, "button[phx-click='new-api-key']")

    render_click(view, "new-api-key")

    render_submit(view, "save-api-key", %{
      "name" => "liveview-test",
      "scopes" => "user:read",
      "expiresAt" => ""
    })

    issued = live_socket(view).assigns.issued_api_key
    assert is_binary(issued.api_key)
    assert String.starts_with?(issued.api_key, "ks_live_")
    assert render(view) =~ issued.api_key

    render_click(view, "dismiss-api-key-secret")
    refute render(view) =~ issued.api_key

    render_click(view, "filter-api-keys", %{"query" => "liveview-test", "status" => "active"})
    assert live_socket(view).assigns.api_key_query == "liveview-test"
    assert live_socket(view).assigns.api_key_status == "active"

    render_click(view, "rotate-api-key", %{"id" => issued.id})
    replacement = live_socket(view).assigns.issued_api_key
    assert replacement.id != issued.id
    render_click(view, "revoke-api-key", %{"id" => replacement.id})

    assert Enum.any?(
             live_socket(view).assigns.api_key_rows,
             &(&1.id == replacement.id and not is_nil(&1.revoked_at))
           )
  end

  defp login_view(conn, user) do
    {:ok, view, _html} = live(conn, "/")

    render_submit(view, "login", %{
      "username" => user.username,
      "password" => @password
    })

    refute has_element?(view, "#login-form")
    {:ok, view, render(view)}
  end

  defp create_user(attrs \\ %{}) do
    attrs =
      Map.merge(
        %{
          "username" => unique("readonly_user"),
          "nickname" => "只读测试用户",
          "password" => @password,
          "status" => 1
        },
        atom_to_string_keys(attrs)
      )

    %SysUser{user_id: Identity.v7()}
    |> SysUser.create_changeset(attrs)
    |> Repo.insert!()
  end

  defp insert_role(%{permission: permission} = attrs) do
    role =
      %SysRole{role_id: Identity.v7()}
      |> SysRole.changeset(%{
        role_name: unique("只读角色"),
        role_key: unique("readonly_role"),
        role_sort: 1,
        data_scope: Map.get(attrs, :data_scope, "ALL"),
        dept_id_set: "",
        status: 1
      })
      |> Repo.insert!()

    menu =
      %SysMenu{menu_id: Identity.v7()}
      |> SysMenu.changeset(%{
        menu_name: unique("只读权限"),
        menu_type: 0,
        parent_id: nil,
        is_button: true,
        permission: permission,
        status: 1
      })
      |> Repo.insert!()

    Repo.insert!(%SysRoleMenu{role_id: role.role_id, menu_id: menu.menu_id})

    permission_entry =
      Repo.get_by(SysPermission, permission: permission) ||
        Repo.insert!(%SysPermission{
          permission_id: Identity.permission_id(permission),
          permission: permission,
          resource: permission |> String.split(":") |> Enum.at(0),
          domain: "default",
          action: permission |> String.split(":") |> List.last(),
          status: 1,
          deprecated: false
        })

    Repo.insert!(%SysRolePermission{
      role_id: role.role_id,
      permission_id: permission_entry.permission_id
    })

    role
  end

  defp create_monitor_user(permission) do
    role = insert_role(%{permission: permission})
    create_user(%{role_id: role.role_id})
  end

  defp insert_dept(name) do
    %SysDept{dept_id: Identity.v7()}
    |> SysDept.changeset(%{dept_name: "#{name} #{unique("dept")}", ancestors: "", status: 1})
    |> Repo.insert!()
  end

  defp clear_config_cache, do: Cache.delete_prefix("keystone:system:config:")

  defp insert_dict_fixture do
    dict_type =
      %DictType{}
      |> DictType.changeset(%{
        dict_name: "只读字典",
        dict_type: "readonly.type",
        status: 1,
        remark: ""
      })
      |> Repo.insert!()

    %DictData{}
    |> DictData.changeset(%{
      dict_type: dict_type.dict_type,
      dict_label: "只读值",
      dict_value: 1,
      dict_sort: 1,
      is_default: false,
      status: 1,
      remark: ""
    })
    |> Repo.insert!()
  end

  defp ensure_captcha_disabled do
    case Repo.get_by(SysConfig, config_key: @captcha_config_key, deleted: false) do
      nil ->
        %SysConfig{}
        |> SysConfig.changeset(%{
          config_name: "账号自助-验证码开关",
          config_key: @captcha_config_key,
          config_options: Jason.encode!(["true", "false"]),
          config_value: "false",
          is_allow_change: false,
          remark: "readonly panel test"
        })
        |> Repo.insert!()

      config ->
        Repo.update!(Ecto.Changeset.change(config, config_value: "false"))
    end
  end

  defp atom_to_string_keys(attrs) do
    Enum.reduce(attrs, %{}, fn
      {key, value}, result when is_atom(key) -> Map.put(result, Atom.to_string(key), value)
      {key, value}, result -> Map.put(result, key, value)
    end)
  end

  defp live_socket(view), do: find_socket(:sys.get_state(view.pid))

  defp find_socket(%Phoenix.LiveView.Socket{} = socket), do: socket
  defp find_socket(%{} = map), do: map |> Map.values() |> Enum.find_value(&find_socket/1)

  defp find_socket(tuple) when is_tuple(tuple),
    do: tuple |> Tuple.to_list() |> Enum.find_value(&find_socket/1)

  defp find_socket(list) when is_list(list), do: Enum.find_value(list, &find_socket/1)
  defp find_socket(_value), do: nil

  defp unique(prefix), do: "#{prefix}_#{System.unique_integer([:positive])}"
end
