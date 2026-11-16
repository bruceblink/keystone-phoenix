defmodule KeystonePhoenixWeb.ManagementReadControllerTest do
  use KeystonePhoenixWeb.ConnCase, async: false

  alias KeystonePhoenix.Auth
  alias KeystonePhoenix.Authz.{PolicyCache, SysPermission, SysRolePermission}
  alias KeystonePhoenix.Identity
  alias KeystonePhoenix.Repo
  alias KeystonePhoenix.Role.SysRole
  alias KeystonePhoenix.User.SysUser

  @tag :integration
  test "管理员可以通过 HTTP 读取配置、字典和公告管理数据" do
    token = admin_token()
    conn = authorized(build_conn(), token)

    assert %{"success" => true, "data" => _configs} =
             json_response(get(conn, "/api/v1/configs"), 200)

    assert %{"success" => true, "data" => _types} =
             json_response(get(authorized(build_conn(), token), "/api/v1/dictionaries"), 200)

    assert %{"success" => true, "data" => _notices} =
             json_response(get(authorized(build_conn(), token), "/api/v1/notices/manage"), 200)
  end

  @tag :integration
  test "配置列表在提供 page 和 size 时返回分页契约" do
    token = admin_token()
    config_key = Identity.v7()

    response =
      post(authorized(build_conn(), token), "/api/v1/configs", %{
        "configName" => "分页配置",
        "configKey" => config_key,
        "configValue" => "page",
        "isAllowChange" => 1
      })

    assert response.status == 201

    assert %{
             "success" => true,
             "data" => %{
               "items" => items,
               "page" => 1,
               "size" => 1,
               "total" => total
             }
           } =
             get(authorized(build_conn(), token), "/api/v1/configs", %{
               "page" => "1",
               "size" => "1",
               "keyword" => "分页配置"
             })
             |> json_response(200)

    assert total >= 1
    assert Enum.any?(items, &(&1["key"] == config_key))
    assert delete(authorized(build_conn(), token), "/api/v1/configs/#{config_key}").status == 200
  end

  @tag :integration
  test "字典类型和条目通过 HTTP 创建后可以按类型读取并清理" do
    token = admin_token()
    # 使用 UUID 形状的 code，覆盖 Native 允许的业务键边界。
    dict_type = Identity.v7()

    type_response =
      post(authorized(build_conn(), token), "/api/v1/dictionaries", %{
        "dictName" => "HTTP 查询字典",
        "dictType" => dict_type,
        "status" => 1
      })

    assert type_response.status == 201

    assert Enum.any?(
             get(authorized(build_conn(), token), "/api/v1/dictionaries", %{
               "dictType" => dict_type
             })
             |> json_response(200)
             |> get_in(["data"]),
             &(&1["code"] == dict_type)
           )

    data_response =
      post(authorized(build_conn(), token), "/api/v1/dictionaries/#{dict_type}/items", %{
        "dictType" => dict_type,
        "dictLabel" => "已启用",
        "dictValue" => 1,
        "status" => 1
      })

    assert data_response.status == 201

    assert %{"success" => true, "data" => rows} =
             json_response(
               get(authorized(build_conn(), token), "/api/v1/dictionaries/#{dict_type}/items"),
               200
             )

    assert Enum.any?(rows, &(&1["typeCode"] == dict_type))

    assert %{
             "success" => true,
             "data" => %{
               "items" => items,
               "page" => 1,
               "size" => 1,
               "total" => total
             }
           } =
             get(
               authorized(build_conn(), token),
               "/api/v1/dictionaries/#{dict_type}/items",
               %{"page" => "1", "size" => "1", "keyword" => "已启用"}
             )
             |> json_response(200)

    assert total >= 1
    assert Enum.any?(items, &(&1["typeCode"] == dict_type))

    data_code = Enum.find(rows, &(&1["typeCode"] == dict_type))["id"]

    assert delete(authorized(build_conn(), token), "/api/v1/dictionaries/items/#{data_code}").status ==
             200

    assert delete(authorized(build_conn(), token), "/api/v1/dictionaries/types/#{dict_type}").status ==
             200
  end

  @tag :integration
  test "管理员可以通过 HTTP 完成配置和公告的新增、修改与删除" do
    token = admin_token()
    # 使用 UUID 形状的 key，避免把业务 key 错当成配置主键。
    config_key = Identity.v7()
    notice_title = "HTTP 写入公告 #{System.unique_integer([:positive])}"

    config_response =
      post(authorized(build_conn(), token), "/api/v1/configs", %{
        "configName" => "HTTP 写入配置",
        "configKey" => config_key,
        "configValue" => "初始值",
        "isAllowChange" => 1
      })

    assert config_response.status == 201

    config_id =
      get(authorized(build_conn(), token), "/api/v1/configs", %{"configKey" => config_key})
      |> json_response(200)
      |> get_in(["data", Access.at(0), "id"])

    assert put(authorized(build_conn(), token), "/api/v1/configs/#{config_key}", %{
             "configValue" => "更新值"
           }).status == 200

    assert get(authorized(build_conn(), token), "/api/v1/configs/#{config_key}")
           |> json_response(200)
           |> get_in(["data", "value"]) == "更新值"

    assert post(authorized(build_conn(), token), "/api/v1/notices", %{
             "title" => notice_title,
             "noticeType" => "notification",
             "content" => "HTTP 写入内容",
             "enabled" => true
           }).status == 201

    notice_id =
      get(authorized(build_conn(), token), "/api/v1/notices/manage", %{
        "title" => notice_title
      })
      |> json_response(200)
      |> get_in(["data", Access.at(0), "id"])

    assert put(authorized(build_conn(), token), "/api/v1/notices/#{notice_id}", %{
             "enabled" => false
           }).status == 200

    assert post(authorized(build_conn(), token), "/api/v1/notices/#{notice_id}/publish", %{
             "published" => true
           }).status == 200

    assert delete(authorized(build_conn(), token), "/api/v1/notices/#{notice_id}").status == 200

    assert delete(authorized(build_conn(), token), "/api/v1/configs/#{config_key}").status == 200

    Repo.get!(KeystonePhoenix.Config.SysConfig, config_id)
    |> Ecto.Changeset.change(deleted: true)
    |> Repo.update!()
  end

  @tag :integration
  test "公告管理列表在提供 page 和 size 时返回 Native 分页契约" do
    token = admin_token()
    title = "分页公告 #{System.unique_integer([:positive])}"

    response =
      post(authorized(build_conn(), token), "/api/v1/notices", %{
        "title" => title,
        "content" => "分页公告内容",
        "noticeType" => "notification",
        "enabled" => true
      })

    assert response.status == 201

    assert %{
             "success" => true,
             "data" => %{
               "items" => [item],
               "page" => 1,
               "size" => 1,
               "total" => total
             }
           } =
             get(authorized(build_conn(), token), "/api/v1/notices/manage", %{
               "page" => "1",
               "size" => "1",
               "title" => title
             })
             |> json_response(200)

    assert total == 1
    assert item["title"] == title
    assert item["enabled"] == true
    assert delete(authorized(build_conn(), token), "/api/v1/notices/#{item["id"]}").status == 200
  end

  @tag :integration
  test "管理资源新增保留 admin-web 传入的停用状态" do
    token = admin_token()
    suffix = System.unique_integer([:positive])

    department_response =
      post(authorized(build_conn(), token), "/api/v1/departments", %{
        "code" => "HTTP_DISABLED_DEPT_#{suffix}",
        "name" => "HTTP 停用组织",
        "parentId" => nil,
        "sortOrder" => 1,
        "enabled" => false
      })

    assert department_response.status == 201
    department = json_response(department_response, 201)["data"]
    assert department["enabled"] == false

    assert delete(authorized(build_conn(), token), "/api/v1/departments/#{department["id"]}").status ==
             200

    post_response =
      post(authorized(build_conn(), token), "/api/v1/posts", %{
        "code" => "HTTP_DISABLED_POST_#{suffix}",
        "name" => "HTTP 停用岗位",
        "sortOrder" => 1,
        "enabled" => false
      })

    assert post_response.status == 201
    post_row = json_response(post_response, 201)["data"]
    assert post_row["enabled"] == false

    assert delete(authorized(build_conn(), token), "/api/v1/posts/#{post_row["id"]}").status ==
             200

    menu_response =
      post(authorized(build_conn(), token), "/api/v1/menus", %{
        "code" => "http_disabled_menu_#{suffix}",
        "name" => "HTTP 停用菜单",
        "parentId" => nil,
        "path" => "/http-disabled-menu-#{suffix}",
        "component" => nil,
        "menuType" => "MENU",
        "permission" => nil,
        "sortOrder" => 1,
        "enabled" => false
      })

    assert menu_response.status == 201
    menu = json_response(menu_response, 201)["data"]
    assert menu["enabled"] == false
    assert delete(authorized(build_conn(), token), "/api/v1/menus/#{menu["id"]}").status == 200

    config_key = "http.disabled.config.#{suffix}"

    config_response =
      post(authorized(build_conn(), token), "/api/v1/configs", %{
        "key" => config_key,
        "value" => "disabled",
        "description" => "HTTP 停用配置",
        "enabled" => false
      })

    assert config_response.status == 201
    config = json_response(config_response, 201)["data"]
    assert config["enabled"] == false
    assert delete(authorized(build_conn(), token), "/api/v1/configs/#{config_key}").status == 200

    dict_code = "http_disabled_dict_#{suffix}"

    dict_response =
      post(authorized(build_conn(), token), "/api/v1/dictionaries", %{
        "code" => dict_code,
        "name" => "HTTP 停用字典",
        "enabled" => false
      })

    assert dict_response.status == 201
    dict_type = json_response(dict_response, 201)["data"]
    assert dict_type["enabled"] == false

    assert put(authorized(build_conn(), token), "/api/v1/dictionaries/types/#{dict_code}", %{
             "name" => "HTTP 启用字典",
             "enabled" => true
           }).status == 200

    item_response =
      post(authorized(build_conn(), token), "/api/v1/dictionaries/#{dict_code}/items", %{
        "value" => "disabled",
        "label" => "停用",
        "sortOrder" => 1,
        "enabled" => false
      })

    assert item_response.status == 201
    item = json_response(item_response, 201)["data"]
    assert item["enabled"] == false

    assert delete(authorized(build_conn(), token), "/api/v1/dictionaries/items/#{item["id"]}").status ==
             200

    assert delete(authorized(build_conn(), token), "/api/v1/dictionaries/types/#{dict_code}").status ==
             200
  end

  @tag :integration
  test "菜单使用未登记权限标识时返回校验错误而不是服务器错误" do
    token = admin_token()

    response =
      post(authorized(build_conn(), token), "/api/v1/menus", %{
        "code" => "http_invalid_permission_#{System.unique_integer([:positive])}",
        "name" => "HTTP 无效权限菜单",
        "menuType" => "MENU",
        "component" => "",
        "permission" => "unknown:permission",
        "enabled" => true
      })

    assert response.status == 422
    assert get_in(json_response(response, 422), ["error", "code"]) == "validation_failed"
  end

  defp admin_token do
    role =
      %SysRole{}
      |> SysRole.changeset(%{
        role_name: "管理读取测试",
        role_key: "management_read_#{System.unique_integer([:positive])}",
        role_sort: 1,
        data_scope: "TENANT",
        status: 1
      })
      |> Repo.insert!()

    for permission <-
          ~w(config:read config:create config:update department:read department:create department:update department:delete dictionary:read dictionary:create dictionary:update dictionary:delete menu:read menu:create menu:update menu:delete menu:manage post:read post:create post:update post:delete notice:read notice:create notice:update notice:delete) do
      permission_id = Repo.get_by!(SysPermission, permission: permission).permission_id
      Repo.insert!(%SysRolePermission{role_id: role.role_id, permission_id: permission_id})
    end

    PolicyCache.invalidate()

    user =
      %SysUser{user_id: Identity.v7()}
      |> SysUser.create_changeset(%{
        username: "management_read_#{System.unique_integer([:positive])}",
        password: "Strong!123",
        role_id: role.role_id,
        status: 1
      })
      |> Repo.insert!()

    {:ok, tokens} = Auth.login_plaintext(user.username, "Strong!123")
    tokens.token
  end

  # 统一使用 Bearer 令牌，确保测试经过真实认证和资源授权入口。
  defp authorized(conn, token),
    do: Plug.Conn.put_req_header(conn, "authorization", "Bearer #{token}")
end
