defmodule KeystonePhoenixWeb.AdminConfigPermissionLiveTest do
  use KeystonePhoenixWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias KeystonePhoenix.Config.SysConfig
  alias KeystonePhoenix.Identity
  alias KeystonePhoenix.Repo
  alias KeystonePhoenix.Authz.{SysPermission, SysRolePermission}
  alias KeystonePhoenix.Role.SysRole
  alias KeystonePhoenix.User.SysUser
  alias KeystonePhoenixWeb.Live.AdminEvents.Config, as: ConfigEvents
  alias KeystonePhoenixWeb.Live.AdminPages.System

  @tag :integration
  test "read-only users see no configuration write actions", %{conn: conn} do
    config = create_config("read_only")
    {user, _role} = create_actor(["config:read"])
    {:ok, view} = login(conn, user)
    render_click(view, "show-panel", %{"panel" => "configs"})

    assert has_element?(view, ".configs-page")
    assert has_element?(view, "code.config-key", config.config_key)
    refute has_element?(view, "th[scope='col']", "操作")
    refute has_element?(view, "button[phx-click='new-config']")
    refute has_element?(view, "button[phx-click='edit-config']")
    refute has_element?(view, "button[phx-click='delete-config']")
  end

  @tag :integration
  test "create-only users can create but cannot edit or delete configurations", %{conn: conn} do
    {user, _role} = create_actor(["config:read", "config:create"])
    {:ok, view} = login(conn, user)
    render_click(view, "show-panel", %{"panel" => "configs"})

    assert has_element?(view, "button[phx-click='new-config']")
    refute has_element?(view, "button[phx-click='edit-config']")
    refute has_element?(view, "button[phx-click='delete-config']")

    render_click(view, "new-config")
    assert has_element?(view, "#config-modal form[phx-submit='save-config']")

    render_submit(view, "save-config", config_params("create_only"))

    assert render(view) =~ "配置已创建"
    assert has_element?(view, "code.config-key", "live.config.create_only")
    refute has_element?(view, "button[phx-click='edit-config']")
    refute has_element?(view, "button[phx-click='delete-config']")
  end

  @tag :integration
  test "update-only users can edit and delete but cannot create configurations", %{conn: conn} do
    config = create_config("update_only")
    {user, _role} = create_actor(["config:read", "config:update"])
    {:ok, view} = login(conn, user)
    render_click(view, "show-panel", %{"panel" => "configs"})

    refute has_element?(view, "button[phx-click='new-config']")
    assert has_element?(view, "button[phx-click='edit-config']")
    assert has_element?(view, "button[phx-click='delete-config']")
    assert has_element?(view, "th[scope='col']", "操作")

    render_click(view, "edit-config", %{"config-id" => to_string(config.config_id)})
    assert has_element?(view, "#config-modal form[phx-submit='save-config']")

    render_submit(
      view,
      "save-config",
      Map.put(config_params("update_only"), "configId", to_string(config.config_id))
      |> Map.put("configValue", "updated")
    )

    assert render(view) =~ "配置已更新"
    assert Repo.get!(SysConfig, config.config_id).config_value == "updated"

    render_click(view, "delete-config", %{"config-id" => to_string(config.config_id)})
    assert render(view) =~ "配置已删除"
    assert Repo.get!(SysConfig, config.config_id).deleted
  end

  @tag :integration
  test "a removed update permission blocks a form that was already open", %{conn: conn} do
    config = create_config("permission_changed")
    {user, _role} = create_actor(["config:read", "config:update"])
    {:ok, view} = login(conn, user)
    render_click(view, "show-panel", %{"panel" => "configs"})
    render_click(view, "edit-config", %{"config-id" => to_string(config.config_id)})
    assert has_element?(view, "#config-modal form[phx-submit='save-config']")

    # 模拟授权刷新后，此表单的服务端会话只保留读取权限。
    socket = Phoenix.Component.assign(live_socket(view), :permissions, ["config:read"])

    assert {:noreply, rejected} =
             ConfigEvents.handle_event(
               "save-config",
               Map.put(
                 config_params("permission_changed"),
                 "configId",
                 to_string(config.config_id)
               )
               |> Map.put("configValue", "must_not_write"),
               socket
             )

    assert KeystonePhoenixWeb.Live.AdminPages.Feedback.code(rejected.assigns.config_feedback) ==
             "permission_denied"

    assert Repo.get!(SysConfig, config.config_id).config_value == "original"
  end

  test "a changed permission set removes the matching modal form" do
    config = %{"configId" => "existing-config"}

    html =
      render_component(&System.configs/1, %{
        config_rows: [],
        config_form: config,
        config_feedback: nil,
        active_modal: "config",
        permissions: ["config:read"]
      })

    refute html =~ ~s(phx-submit="save-config")
    assert html =~ "当前账号已失去此项配置写权限"
  end

  # 使用真实角色权限建立最小权限账号，覆盖页面显示与事件授权。
  defp create_actor(permissions) do
    role =
      %SysRole{role_id: Identity.v7()}
      |> SysRole.changeset(%{
        role_name: unique("配置权限角色"),
        role_key: unique("config_permission_role"),
        role_sort: 1,
        data_scope: "ALL",
        dept_id_set: "",
        status: 1
      })
      |> Repo.insert!()

    Enum.each(permissions, fn code ->
      permission = Repo.get_by!(SysPermission, permission: code)

      Repo.insert!(%SysRolePermission{
        role_id: role.role_id,
        permission_id: permission.permission_id
      })
    end)

    user =
      Repo.insert!(%SysUser{
        user_id: Identity.v7(),
        role_id: role.role_id,
        username: unique("config_permission_user"),
        password: Bcrypt.hash_pwd_salt("Strong!123"),
        status: 1
      })

    {user, role}
  end

  # 配置记录直接写入隔离测试库，避免测试主体需要额外的创建权限。
  defp create_config(suffix) do
    Repo.insert!(
      SysConfig.changeset(%SysConfig{}, %{
        config_name: "配置权限验收",
        config_key: "live.config.#{suffix}.#{Elixir.System.unique_integer([:positive])}",
        config_value: "original",
        is_allow_change: true
      })
    )
  end

  defp config_params(suffix) do
    %{
      "configId" => "",
      "configName" => "权限验收 #{suffix}",
      "configKey" => "live.config.#{suffix}",
      "configOptions" => "",
      "configValue" => "original",
      "isAllowChange" => "true",
      "remark" => ""
    }
  end

  defp login(conn, user) do
    {:ok, view, _html} = live(conn, "/")
    render_submit(view, "login", %{"username" => user.username, "password" => "Strong!123"})
    {:ok, view}
  end

  defp live_socket(view), do: find_socket(:sys.get_state(view.pid))
  defp find_socket(%Phoenix.LiveView.Socket{} = socket), do: socket
  defp find_socket(%{} = map), do: map |> Map.values() |> Enum.find_value(&find_socket/1)

  defp find_socket(tuple) when is_tuple(tuple),
    do: tuple |> Tuple.to_list() |> Enum.find_value(&find_socket/1)

  defp find_socket(list) when is_list(list), do: Enum.find_value(list, &find_socket/1)
  defp find_socket(_value), do: nil
  defp unique(prefix), do: "#{prefix}_#{Elixir.System.unique_integer([:positive])}"
end
