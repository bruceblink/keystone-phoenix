defmodule KeystonePhoenixWeb.AdminEditingTest do
  use KeystonePhoenixWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias KeystonePhoenix.{Auth, Cache, Config, Dictionary, Identity, Menu, Repo, Role}
  alias KeystonePhoenix.Auth.Mfa
  alias KeystonePhoenix.Auth.Mfa.Totp
  alias KeystonePhoenix.Authz.{SysPermission, SysRolePermission}
  alias KeystonePhoenix.Config.SysConfig
  alias KeystonePhoenix.Menu.SysMenu
  alias KeystonePhoenix.Role.SysRole
  alias KeystonePhoenix.User.SysUser
  alias KeystonePhoenixWeb.Live.AdminPages.Operations

  setup do
    clear_config_cache()
    on_exit(&clear_config_cache/0)

    admin_role =
      %SysRole{role_id: Identity.v7()}
      |> SysRole.changeset(%{
        role_name: unique("编辑管理员角色"),
        role_key: unique("editing_admin_role"),
        role_sort: 1,
        data_scope: "ALL",
        dept_id_set: "",
        status: 1
      })
      |> Repo.insert!()

    for permission <- Repo.all(SysPermission) do
      Repo.insert!(%SysRolePermission{
        role_id: admin_role.role_id,
        permission_id: permission.permission_id
      })
    end

    admin =
      Repo.insert!(%SysUser{
        user_id: Identity.v7(),
        role_id: admin_role.role_id,
        username: unique("editing_admin"),
        password: Bcrypt.hash_pwd_salt("Strong!123"),
        status: 1
      })

    {:ok, admin: admin}
  end

  test "config edit preserves the ID and saved fields before updating one row", ctx do
    {:ok, config} =
      Config.create_config(
        %{
          "configName" => "原配置名称",
          "configKey" => unique("editing.config"),
          "configOptions" => ~s(["alpha","beta"]),
          "configValue" => "alpha",
          "isAllowChange" => true
        },
        authorization: %{principal: ctx.admin}
      )

    {:ok, view} = login(ctx.conn, ctx.admin)
    render_click(view, "show-panel", %{"panel" => "configs"})
    render_click(view, "edit-config", %{"config-id" => to_string(config.config_id)})
    assert live_socket(view).assigns.active_modal == "config"
    assert has_element?(view, "input[name='configId'][value='#{config.config_id}']")
    assert has_element?(view, "#config-name[value='原配置名称']")
    assert has_element?(view, "#config-key[value='#{config.config_key}']")

    count = Repo.aggregate(SysConfig, :count)

    view
    |> form("form[phx-submit='save-config']", %{"configValue" => "beta"})
    |> render_submit()

    assert render(view) =~ "配置已更新"
    assert live_socket(view).assigns.active_modal == nil
    assert Repo.aggregate(SysConfig, :count) == count
    assert Repo.get!(SysConfig, config.config_id).config_value == "beta"
  end

  test "role edit preserves the ID and updates the original row", ctx do
    {:ok, role} =
      Role.create_role(
        %{
          "roleName" => unique("原角色"),
          "roleKey" => unique("editing_role"),
          "roleSort" => 7,
          "dataScope" => "DEPARTMENT",
          "status" => 1,
          "menuIds" => []
        },
        authorization: %{principal: ctx.admin, permission: "role:create"}
      )

    {:ok, view} = login_with_step_up(ctx.conn, ctx.admin)
    render_click(view, "show-panel", %{"panel" => "roles"})
    render_click(view, "edit-role", %{"role-id" => to_string(role.role_id)})
    assert live_socket(view).assigns.active_modal == "role"
    assert has_element?(view, "input[name='roleId'][value='#{role.role_id}']")
    assert has_element?(view, "input[name='roleKey'][value='#{role.role_key}']")
    count = Repo.aggregate(SysRole, :count)

    view
    |> form("form[phx-submit='save-role']", %{"roleName" => "角色已修改"})
    |> render_submit()

    assert render(view) =~ "角色已更新"
    assert live_socket(view).assigns.active_modal == nil
    assert Repo.aggregate(SysRole, :count) == count
    assert Repo.get!(SysRole, role.role_id).role_name == "角色已修改"
    assert Repo.get!(SysRole, role.role_id).data_scope == "DEPARTMENT"
  end

  test "organization missing records expose a stable not-found feedback code", ctx do
    {:ok, view} = login_with_step_up(ctx.conn, ctx.admin)
    render_click(view, "show-panel", %{"panel" => "roles"})
    render_click(view, "edit-role", %{"role-id" => Identity.v7()})

    feedback = live_socket(view).assigns.role_feedback
    assert KeystonePhoenixWeb.Live.AdminPages.Feedback.code(feedback) == "resource_not_found"
    assert KeystonePhoenixWeb.Live.AdminPages.Feedback.message(feedback) == "找不到指定角色"
  end

  test "refreshing or deleting a role clears its selected users", ctx do
    {:ok, role} =
      Role.create_role(
        %{
          "roleName" => unique("待清理角色"),
          "roleKey" => unique("stale_role"),
          "roleSort" => 7,
          "dataScope" => "DEPARTMENT",
          "status" => 1,
          "menuIds" => []
        },
        authorization: %{principal: ctx.admin, permission: "role:create"}
      )

    {:ok, view} = login_with_step_up(ctx.conn, ctx.admin)
    render_click(view, "show-panel", %{"panel" => "roles"})
    render_click(view, "select-role", %{"role-id" => to_string(role.role_id)})
    assert has_element?(view, "#role-user-management")

    render_click(view, "refresh-roles")
    refute has_element?(view, "#role-user-management")
    assert live_socket(view).assigns.selected_role_id == ""
    assert live_socket(view).assigns.selected_role_name == ""
    assert live_socket(view).assigns.allocated_role_user_rows == []
    assert live_socket(view).assigns.unallocated_role_user_rows == []
    assert live_socket(view).assigns.role_user_feedback == nil

    render_click(view, "select-role", %{"role-id" => to_string(role.role_id)})
    assert has_element?(view, "#role-user-management")
    render_click(view, "delete-role", %{"role-id" => to_string(role.role_id)})

    refute has_element?(view, "#role-user-management")
    assert live_socket(view).assigns.selected_role_id == ""
    assert live_socket(view).assigns.selected_role_name == ""
    assert live_socket(view).assigns.allocated_role_user_rows == []
    assert live_socket(view).assigns.unallocated_role_user_rows == []
    assert live_socket(view).assigns.role_user_feedback == nil
  end

  test "role list supports selecting the current result set", ctx do
    roles =
      for suffix <- ["one", "two"] do
        {:ok, role} =
          Role.create_role(
            %{
              "roleName" => unique("选择角色 #{suffix}"),
              "roleKey" => unique("selection_#{suffix}"),
              "roleSort" => 7,
              "dataScope" => "ALL",
              "status" => 1,
              "menuIds" => []
            },
            authorization: %{principal: ctx.admin, permission: "role:create"}
          )

        role
      end

    {:ok, view} = login(ctx.conn, ctx.admin)
    render_click(view, "show-panel", %{"panel" => "roles"})
    assert has_element?(view, "input[aria-label='选择当前角色']")

    render_click(view, "toggle-all-role-selection", %{"selected" => "true"})
    selected_ids = live_socket(view).assigns.selected_role_ids
    assert Enum.all?(roles, &(to_string(&1.role_id) in selected_ids))

    render_click(view, "toggle-role-selection", %{
      "role-id" => to_string(hd(roles).role_id),
      "selected" => "false"
    })

    refute to_string(hd(roles).role_id) in live_socket(view).assigns.selected_role_ids
    assert to_string(List.last(roles).role_id) in live_socket(view).assigns.selected_role_ids

    render_click(view, "paginate", %{"panel" => "roles", "page" => "2"})
    assert live_socket(view).assigns.selected_role_ids == []

    render_click(view, "refresh-roles", %{"reset" => "true"})
    assert live_socket(view).assigns.selected_role_ids == []
  end

  test "menu edit preserves the ID and saved route fields", ctx do
    {:ok, menu} =
      Menu.create_menu(
        %{
          "menuName" => unique("原菜单"),
          "menuType" => 1,
          "routerName" => unique("EditingRoute"),
          "parentId" => nil,
          "path" => "/editing-route",
          "isButton" => false,
          "permission" => "menu:read",
          "metaInfo" => ~s({"title":"原菜单"}),
          "status" => 1
        },
        authorization: %{principal: ctx.admin, permission: "menu:create"}
      )

    {:ok, view} = login(ctx.conn, ctx.admin)
    render_click(view, "show-panel", %{"panel" => "menus"})
    render_click(view, "edit-menu", %{"menu-id" => to_string(menu.menu_id)})
    assert live_socket(view).assigns.active_modal == "menu"
    assert has_element?(view, "input[name='menuId'][value='#{menu.menu_id}']")
    assert has_element?(view, "input[name='path'][value='/editing-route']")
    count = Repo.aggregate(SysMenu, :count)

    view
    |> form("form[phx-submit='save-menu']", %{"name" => "菜单已修改"})
    |> render_submit()

    assert render(view) =~ "菜单已更新"
    assert live_socket(view).assigns.active_modal == nil
    assert Repo.aggregate(SysMenu, :count) == count
    updated = Repo.get!(SysMenu, menu.menu_id)
    assert updated.menu_name == "菜单已修改"
    assert updated.path == "/editing-route"
    assert updated.router_name == menu.router_name
  end

  test "menu edit reads and replaces role bindings", ctx do
    {:ok, menu} =
      Menu.create_menu(
        %{
          "code" => unique("role_binding_menu"),
          "name" => unique("角色绑定菜单"),
          "menuType" => "MENU",
          "path" => "/role-binding-menu",
          "permission" => "menu:read",
          "enabled" => true
        },
        authorization: %{principal: ctx.admin, permission: "menu:create"}
      )

    {:ok, role} =
      Role.create_role(
        %{
          "roleName" => unique("可访问菜单角色"),
          "roleKey" => unique("menu_access_role"),
          "roleSort" => 8,
          "dataScope" => "ALL",
          "status" => 1,
          "menuIds" => []
        },
        authorization: %{principal: ctx.admin, permission: "role:create"}
      )

    {:ok, view} = login(ctx.conn, ctx.admin)
    render_click(view, "show-panel", %{"panel" => "menus"})
    render_click(view, "edit-menu", %{"menu-id" => to_string(menu.menu_id)})
    assert has_element?(view, "#menu-role-codes input[value='#{role.role_key}']")
    refute has_element?(view, "#menu-role-codes input[value='#{role.role_key}'][checked]")

    render_submit(view, "save-menu", %{
      "menuId" => to_string(menu.menu_id),
      "name" => menu.menu_name,
      "code" => menu.menu_code,
      "menuRoleCodes[]" => [role.role_key]
    })

    assert render(view) =~ "菜单已更新"
    assert Role.menu_ids_for_role(role.role_id) == [menu.menu_id]

    render_click(view, "edit-menu", %{"menu-id" => to_string(menu.menu_id)})
    assert has_element?(view, "#menu-role-codes input[value='#{role.role_key}'][checked]")

    render_submit(view, "save-menu", %{
      "menuId" => to_string(menu.menu_id),
      "name" => menu.menu_name,
      "code" => menu.menu_code,
      "menuRoleCodes[]" => []
    })

    assert Role.menu_ids_for_role(role.role_id) == []
  end

  test "role edit renders and saves selected menu bindings", ctx do
    {:ok, menu} =
      Menu.create_menu(
        %{
          "code" => unique("binding_menu"),
          "name" => unique("绑定菜单"),
          "menuType" => "MENU",
          "path" => "/binding-menu",
          "permission" => "menu:read",
          "enabled" => true
        },
        authorization: %{principal: ctx.admin, permission: "menu:create"}
      )

    {:ok, role} =
      Role.create_role(
        %{
          "roleName" => unique("菜单绑定角色"),
          "roleKey" => unique("menu_binding_role"),
          "roleSort" => 7,
          "dataScope" => "ALL",
          "status" => 1,
          "menuIds" => ""
        },
        authorization: %{principal: ctx.admin, permission: "role:create"}
      )

    {:ok, view} = login_with_step_up(ctx.conn, ctx.admin)
    render_click(view, "show-panel", %{"panel" => "roles"})
    render_click(view, "edit-role", %{"role-id" => to_string(role.role_id)})

    assert has_element?(view, "#role-menu-ids option[value='#{menu.menu_id}']")
    refute has_element?(view, "#role-menu-ids option[value='#{menu.menu_id}'][selected]")

    view
    |> form("form[phx-submit='save-role']", %{"menuIds" => [to_string(menu.menu_id)]})
    |> render_submit()

    assert render(view) =~ "角色已更新"
    assert Role.menu_ids_for_role(role.role_id) == [menu.menu_id]
  end

  test "menu hierarchy keeps three levels and rejects a descendant parent", ctx do
    {:ok, root} =
      Menu.create_menu(
        %{
          "code" => unique("tree_root"),
          "name" => unique("树根"),
          "menuType" => "DIRECTORY",
          "permission" => "menu:read",
          "enabled" => true
        },
        authorization: %{principal: ctx.admin, permission: "menu:create"}
      )

    {:ok, child} =
      Menu.create_menu(
        %{
          "code" => unique("tree_child"),
          "name" => unique("树子"),
          "parentId" => root.menu_id,
          "menuType" => "DIRECTORY",
          "permission" => "menu:read",
          "enabled" => true
        },
        authorization: %{principal: ctx.admin, permission: "menu:create"}
      )

    {:ok, grandchild} =
      Menu.create_menu(
        %{
          "code" => unique("tree_grandchild"),
          "name" => unique("树孙"),
          "parentId" => child.menu_id,
          "menuType" => "MENU",
          "path" => "/tree-grandchild",
          "permission" => "menu:read",
          "enabled" => true
        },
        authorization: %{principal: ctx.admin, permission: "menu:create"}
      )

    {:ok, view} = login(ctx.conn, ctx.admin)
    render_click(view, "show-panel", %{"panel" => "menus"})
    html = render(view)
    assert html =~ root.menu_name
    assert html =~ child.menu_name
    assert html =~ grandchild.menu_name
    assert :binary.match(html, root.menu_name) < :binary.match(html, child.menu_name)
    assert :binary.match(html, child.menu_name) < :binary.match(html, grandchild.menu_name)

    render_click(view, "edit-menu", %{"menu-id" => to_string(root.menu_id)})
    refute has_element?(view, "#menu-parent option[value='#{child.menu_id}']")
    refute has_element?(view, "#menu-parent option[value='#{grandchild.menu_id}']")

    assert {:error, :invalid_parent} =
             Menu.update_menu(
               root.menu_id,
               %{"parentId" => grandchild.menu_id},
               authorization: %{principal: ctx.admin, permission: "menu:update"}
             )

    assert Repo.get!(SysMenu, root.menu_id).parent_id == nil
  end

  test "non-default dictionary data stays false after editing", ctx do
    type = unique("editing.dict")

    {:ok, _type} =
      Dictionary.create_dict_type(
        %{"dictName" => "编辑测试", "dictType" => type, "status" => 1},
        authorization: %{principal: ctx.admin}
      )

    {:ok, data} =
      Dictionary.create_dict_data(
        %{
          "dictType" => type,
          "dictLabel" => "否",
          "dictValue" => 0,
          "dictSort" => 1,
          "isDefault" => false,
          "status" => 1
        },
        authorization: %{principal: ctx.admin}
      )

    {:ok, view} = login(ctx.conn, ctx.admin)
    render_click(view, "show-panel", %{"panel" => "dicts"})
    render_click(view, "select-dict-type", %{"dict-type" => type})
    render_click(view, "edit-dict-data", %{"dict-code" => to_string(data.dict_code)})
    assert live_socket(view).assigns.active_modal == "dict-data"
    assert has_element?(view, "#dict-default option[value='false'][selected]")

    view
    |> form("form[phx-submit='save-dict-data']", %{"dictLabel" => "仍为否"})
    |> render_submit()

    assert render(view) =~ "字典数据已更新"
    assert live_socket(view).assigns.active_modal == nil
    assert Repo.get!(KeystonePhoenix.Dictionary.DictData, data.dict_code).is_default == false
    assert Dictionary.list_dict_data(%{"dictType" => type}).total == 1
  end

  test "the operation-log panel is read-only", ctx do
    {:ok, view} = login(ctx.conn, ctx.admin)
    render_click(view, "show-panel", %{"panel" => "logs"})
    refute has_element?(view, "button[phx-click='delete-operation-log']")
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
    assert has_element?(view, "nav[aria-label='主导航']")
    {:ok, view}
  end

  # 注册测试 TOTP 并通过页面完成 step-up，覆盖角色敏感写操作的真实认证路径。
  defp login_with_step_up(conn, user) do
    {:ok, view} = login(conn, user)
    token = live_socket(view).assigns.access_token
    {:ok, claims} = Auth.Token.verify(token, Auth.Token.access_type())

    {:ok, enrollment} =
      Mfa.begin_enrollment(user.user_id, user.username, claims["client_id"], claims["sid"])

    now = System.system_time(:second)

    {:ok, _verification} =
      Mfa.verify_enrollment(
        user.user_id,
        enrollment.challenge_id,
        claims["client_id"],
        claims["sid"],
        Totp.code(enrollment.secret, now),
        nil
      )

    render_click(view, "logout")
    render_submit(view, "login", %{"username" => user.username, "password" => "Strong!123"})
    render_click(view, "begin-liveview-step-up")

    render_submit(view, "verify-liveview-step-up", %{
      "code" => Totp.code(enrollment.secret, now + Totp.step_seconds())
    })

    refute live_socket(view).assigns.mfa_step_up_required
    {:ok, view}
  end

  defp clear_config_cache, do: Cache.delete_prefix("keystone:system:config:")

  defp live_socket(view), do: find_socket(:sys.get_state(view.pid))

  defp find_socket(%Phoenix.LiveView.Socket{} = socket), do: socket
  defp find_socket(%{} = map), do: map |> Map.values() |> Enum.find_value(&find_socket/1)

  defp find_socket(tuple) when is_tuple(tuple),
    do: tuple |> Tuple.to_list() |> Enum.find_value(&find_socket/1)

  defp find_socket(list) when is_list(list), do: Enum.find_value(list, &find_socket/1)
  defp find_socket(_value), do: nil

  defp unique(prefix), do: "#{prefix}_#{System.unique_integer([:positive])}"
end
