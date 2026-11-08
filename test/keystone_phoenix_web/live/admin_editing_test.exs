defmodule KeystonePhoenixWeb.AdminEditingTest do
  use KeystonePhoenixWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias KeystonePhoenix.{Config, Dictionary, Log, Menu, Repo, Role}
  alias KeystonePhoenix.Config.SysConfig
  alias KeystonePhoenix.Menu.SysMenu
  alias KeystonePhoenix.Role.SysRole
  alias KeystonePhoenix.User.SysUser
  alias KeystonePhoenixWeb.Live.AdminPages.Operations

  setup do
    Config.refresh_cache()
    on_exit(&Config.refresh_cache/0)

    admin =
      Repo.insert!(%SysUser{
        username: unique("editing_admin"),
        password: Bcrypt.hash_pwd_salt("Strong!123"),
        is_admin: true,
        status: 1
      })

    {:ok, admin: admin}
  end

  test "config edit preserves the ID and saved fields before updating one row", ctx do
    {:ok, config} =
      Config.create_config(%{
        "configName" => "原配置名称",
        "configKey" => unique("editing.config"),
        "configOptions" => ~s(["alpha","beta"]),
        "configValue" => "alpha",
        "isAllowChange" => true
      })

    {:ok, view} = login(ctx.conn, ctx.admin)
    render_click(view, "show-panel", %{"panel" => "configs"})
    render_click(view, "edit-config", %{"config-id" => to_string(config.config_id)})
    assert has_element?(view, "input[name='configId'][value='#{config.config_id}']")
    assert has_element?(view, "#config-name[value='原配置名称']")
    assert has_element?(view, "#config-key[value='#{config.config_key}']")

    count = Repo.aggregate(SysConfig, :count)

    view
    |> form("form[phx-submit='save-config']", %{"configValue" => "beta"})
    |> render_submit()

    assert render(view) =~ "配置已更新"
    assert Repo.aggregate(SysConfig, :count) == count
    assert Repo.get!(SysConfig, config.config_id).config_value == "beta"
  end

  test "role edit preserves the ID and updates the original row", ctx do
    {:ok, role} =
      Role.create_role(%{
        "roleName" => unique("原角色"),
        "roleKey" => unique("editing_role"),
        "roleSort" => 7,
        "dataScope" => 3,
        "status" => 1,
        "menuIds" => []
      })

    {:ok, view} = login(ctx.conn, ctx.admin)
    render_click(view, "show-panel", %{"panel" => "roles"})
    render_click(view, "edit-role", %{"role-id" => to_string(role.role_id)})
    assert has_element?(view, "input[name='roleId'][value='#{role.role_id}']")
    assert has_element?(view, "input[name='roleKey'][value='#{role.role_key}']")
    count = Repo.aggregate(SysRole, :count)

    view
    |> form("form[phx-submit='save-role']", %{"roleName" => "角色已修改"})
    |> render_submit()

    assert render(view) =~ "角色已更新"
    assert Repo.aggregate(SysRole, :count) == count
    assert Repo.get!(SysRole, role.role_id).role_name == "角色已修改"
    assert Repo.get!(SysRole, role.role_id).data_scope == 3
  end

  test "menu edit preserves the ID and saved route fields", ctx do
    {:ok, menu} =
      Menu.create_menu(%{
        "menuName" => unique("原菜单"),
        "menuType" => 1,
        "routerName" => unique("EditingRoute"),
        "parentId" => 0,
        "path" => "/editing-route",
        "isButton" => false,
        "permission" => "editing:read",
        "metaInfo" => ~s({"title":"原菜单"}),
        "status" => 1
      })

    {:ok, view} = login(ctx.conn, ctx.admin)
    render_click(view, "show-panel", %{"panel" => "menus"})
    render_click(view, "edit-menu", %{"menu-id" => to_string(menu.menu_id)})
    assert has_element?(view, "input[name='menuId'][value='#{menu.menu_id}']")
    assert has_element?(view, "input[name='path'][value='/editing-route']")
    count = Repo.aggregate(SysMenu, :count)

    view
    |> form("form[phx-submit='save-menu']", %{"menuName" => "菜单已修改"})
    |> render_submit()

    assert render(view) =~ "菜单已更新"
    assert Repo.aggregate(SysMenu, :count) == count
    updated = Repo.get!(SysMenu, menu.menu_id)
    assert updated.menu_name == "菜单已修改"
    assert updated.path == "/editing-route"
    assert updated.router_name == menu.router_name
  end

  test "non-default dictionary data stays false after editing", ctx do
    type = unique("editing.dict")

    {:ok, _type} =
      Dictionary.create_dict_type(%{"dictName" => "编辑测试", "dictType" => type, "status" => 1})

    {:ok, data} =
      Dictionary.create_dict_data(%{
        "dictType" => type,
        "dictLabel" => "否",
        "dictValue" => 0,
        "dictSort" => 1,
        "isDefault" => false,
        "status" => 1
      })

    {:ok, view} = login(ctx.conn, ctx.admin)
    render_click(view, "show-panel", %{"panel" => "dicts"})
    render_click(view, "select-dict-type", %{"dict-type" => type})
    render_click(view, "edit-dict-data", %{"dict-code" => to_string(data.dict_code)})
    assert has_element?(view, "#dict-default option[value='false'][selected]")

    view
    |> form("form[phx-submit='save-dict-data']", %{"dictLabel" => "仍为否"})
    |> render_submit()

    assert render(view) =~ "字典数据已更新"
    assert Repo.get!(KeystonePhoenix.Dictionary.DictData, data.dict_code).is_default == false
    assert Dictionary.list_dict_data(%{"dictType" => type}).total == 1
  end

  test "the operation-log delete button sends its actual operationId", ctx do
    {:ok, log} =
      Log.create_operation_log(
        %{"requestModule" => "编辑测试", "status" => 1},
        ctx.admin,
        "/editing-test",
        "POST"
      )

    {:ok, view} = login(ctx.conn, ctx.admin)
    render_click(view, "show-panel", %{"panel" => "logs"})

    view
    |> element("button[phx-click='delete-operation-log'][phx-value-log-id='#{log.operation_id}']")
    |> render_click()

    assert render(view) =~ "操作日志已删除"
    assert Repo.get!(KeystonePhoenix.Log.SysOperationLog, log.operation_id).deleted == true
  end

  test "job logs render the published endTime field" do
    html =
      render_component(&Operations.job_logs/1, %{
        job_log_rows: [%{"jobName" => "测试任务", "endTime" => "2026-11-08 12:30:45"}],
        job_log_feedback: nil
      })

    assert html =~ "2026-11-08 12:30:45"
  end

  defp login(conn, user) do
    {:ok, view, _html} = live(conn, "/")
    render_submit(view, "login", %{"username" => user.username, "password" => "Strong!123"})
    assert has_element?(view, "nav[aria-label='管理模块']")
    {:ok, view}
  end

  defp unique(prefix), do: "#{prefix}_#{System.unique_integer([:positive])}"
end
