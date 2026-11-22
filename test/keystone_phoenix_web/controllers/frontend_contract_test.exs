defmodule KeystonePhoenixWeb.FrontendContractTest do
  use KeystonePhoenixWeb.ConnCase, async: false

  alias KeystonePhoenix.Auth
  alias KeystonePhoenix.Authz.{SysMenuPermission, SysPermission, SysRolePermission}
  alias KeystonePhoenix.Department.SysDept
  alias KeystonePhoenix.Dictionary.{DictData, DictType}
  alias KeystonePhoenix.Identity
  alias KeystonePhoenix.Menu.SysMenu
  alias KeystonePhoenix.Notice.SysNotice
  alias KeystonePhoenix.Post.SysPost
  alias KeystonePhoenix.Repo
  alias KeystonePhoenix.Role.{SysRole, SysRoleMenu}
  alias KeystonePhoenix.User.SysUser
  alias KeystonePhoenixWeb.ProfileController

  @tag :integration
  test "frontend management APIs preserve the expected DTO shapes", %{conn: conn} do
    fixtures = fixtures()
    conn = put_req_header(conn, "authorization", "Bearer #{fixtures.token}")

    assert %{"success" => true, "data" => menus} =
             json_response(get(conn, "/api/v1/menus"), 200)

    menu_node = Enum.find(menus, &(&1["menu"]["id"] == fixtures.page_menu.menu_id))
    menu = menu_node["menu"]

    assert Map.keys(menu) |> Enum.sort() ==
             ~w(code component enabled id menuType name parentId path permission sortOrder)

    refute Map.has_key?(menu, "menuId")
    refute Map.has_key?(menu, "isButton")
    refute Map.has_key?(menu, "menuTypeStr")
    refute Map.has_key?(menu, "statusStr")

    assert %{"success" => true, "data" => departments} =
             json_response(get(conn, "/api/v1/departments"), 200)

    department = Enum.find(departments, &(&1["id"] == fixtures.department.dept_id))
    assert Map.keys(department) |> Enum.sort() == ~w(code enabled id name parentId sortOrder)
    refute Map.has_key?(department, "deptId")
    refute Map.has_key?(department, "statusStr")

    assert %{"success" => true, "data" => posts} =
             json_response(get(conn, "/api/v1/posts?pageSize=50"), 200)

    post = Enum.find(posts, &(&1["id"] == fixtures.post.post_id))
    assert Map.keys(post) |> Enum.sort() == ~w(code enabled id name sortOrder)
    refute Map.has_key?(post, "postId")
    refute Map.has_key?(post, "statusStr")

    assert %{"success" => true, "data" => users_page} =
             json_response(get(conn, "/api/v1/users?userId=#{fixtures.user.user_id}"), 200)

    user = Enum.find(users_page["items"], &(&1["id"] == fixtures.user.user_id))
    assert user["displayName"] == "契约用户"
    assert user["roles"] == [fixtures.role.role_key]

    assert %{"success" => true, "data" => profile} =
             json_response(get(conn, "/api/v1/profile"), 200)

    assert profile["id"] == fixtures.user.user_id
    assert profile["displayName"] == "契约用户"
    assert profile["roles"] == [fixtures.role.role_key]

    assert %{"success" => true, "data" => dict_data} =
             json_response(get(conn, "/api/v1/dictionaries/contract.status/items"), 200)

    dict = Enum.find(dict_data, &(&1["id"] == fixtures.dict_data.dict_code))
    assert Map.keys(dict) |> Enum.sort() == ~w(enabled id label sortOrder typeCode value)
    refute Map.has_key?(dict, "dictCode")
    refute Map.has_key?(dict, "isDefault")

    assert %{"success" => true, "data" => notices} =
             json_response(get(build_conn(), "/api/v1/notices"), 200)

    notice = Enum.find(notices, &(&1["id"] == fixtures.notice.notice_id))
    assert notice["createdBy"] == fixtures.user.username
  end

  # 使用 Native 资料字段执行 HTTP 写入，再核对数据库和独立读取结果。
  @tag :integration
  test "profile update persists Native fields and returns them from a later read" do
    fixtures = fixtures()

    attrs = %{
      "displayName" => "更新后的展示名",
      "email" => "profile-roundtrip@example.com",
      "phoneNumber" => "13800138000",
      "sex" => 1,
      "avatar" => "/profile/avatar/profile-roundtrip.png"
    }

    response =
      build_conn()
      |> put_req_header("authorization", "Bearer #{fixtures.token}")
      |> put("/api/v1/profile", attrs)

    assert %{"success" => true, "data" => updated_profile} = json_response(response, 200)

    for field <- ["displayName", "email", "phoneNumber", "sex", "avatar"] do
      assert updated_profile[field] == attrs[field]
    end

    # 检查数据库记录，确保成功响应对应真实持久化。
    persisted_user = Repo.get!(SysUser, fixtures.user.user_id)
    assert persisted_user.nickname == attrs["displayName"]
    assert persisted_user.email == attrs["email"]
    assert persisted_user.phone_number == attrs["phoneNumber"]
    assert persisted_user.sex == attrs["sex"]
    assert persisted_user.avatar == attrs["avatar"]

    assert %{"success" => true, "data" => read_profile} =
             build_conn()
             |> put_req_header("authorization", "Bearer #{fixtures.token}")
             |> get("/api/v1/profile")
             |> json_response(200)

    for field <- ["displayName", "email", "phoneNumber", "sex", "avatar"] do
      assert read_profile[field] == attrs[field]
    end
  end

  @tag :integration
  test "profile update rejects missing and whitespace-only display names like Native" do
    fixtures = fixtures()
    original = Repo.get!(SysUser, fixtures.user.user_id)

    # Native 对缺失、空值和纯空白 displayName 都返回 422，Phoenix 保持相同业务码。
    for attrs <- [%{}, %{"displayName" => ""}, %{"displayName" => " \t "}] do
      response =
        build_conn()
        |> put_req_header("authorization", "Bearer #{fixtures.token}")
        |> put("/api/v1/profile", attrs)

      assert response.status == 422
      assert json_response(response, 422)["message"] == "displayName is required"

      assert get_in(json_response(response, 422), ["error", "code"]) ==
               "profile_display_name_required"
    end

    assert Repo.get!(SysUser, fixtures.user.user_id).nickname == original.nickname
  end

  @tag :integration
  test "missing profile uses resource_not_found" do
    fixtures = fixtures()
    Repo.update!(Ecto.Changeset.change(fixtures.user, deleted: true))

    response =
      build_conn()
      |> Plug.Conn.assign(:current_user, %{user_id: fixtures.user.user_id})
      |> ProfileController.show(%{})

    assert response.status == 404
    assert get_in(json_response(response, 404), ["error", "code"]) == "resource_not_found"
  end

  @tag :integration
  test "avatar update rejects missing and blank addresses without changing the saved avatar" do
    fixtures = fixtures()
    auth = fn -> put_req_header(build_conn(), "authorization", "Bearer #{fixtures.token}") end
    avatar = "/profile/avatar/profile-avatar-check.png"

    assert auth.() |> put("/api/v1/profile/avatar", %{"avatar" => avatar}) |> json_response(200)

    # 空地址不能覆盖或清除已经保存的头像。
    for params <- [%{}, %{"avatar" => ""}, %{"avatar" => " \t "}] do
      response = auth.() |> put("/api/v1/profile/avatar", params)
      assert get_in(json_response(response, 422), ["error", "code"]) == "profile_avatar_required"
      assert Repo.get!(SysUser, fixtures.user.user_id).avatar == avatar
    end
  end

  defp fixtures do
    department =
      %SysDept{dept_id: Identity.v7()}
      |> SysDept.changeset(%{dept_name: "契约部门", ancestors: "", status: 1})
      |> Repo.insert!()

    post =
      %SysPost{post_id: Identity.v7()}
      |> SysPost.changeset(%{
        post_code: "contract_post",
        post_name: "契约岗位",
        post_sort: 1,
        status: 1
      })
      |> Repo.insert!()

    role =
      %SysRole{role_id: Identity.v7()}
      |> SysRole.changeset(%{
        role_name: "契约角色",
        role_key: unique("contract_role"),
        role_sort: 1,
        data_scope: "ALL",
        dept_id_set: department.dept_id,
        status: 1
      })
      |> Repo.insert!()

    page_menu = insert_permission(role.role_id, "menu:read", 1, false)
    insert_permission(role.role_id, "role:read", 0, true)
    insert_permission(role.role_id, "department:read", 0, true)
    insert_permission(role.role_id, "post:read", 0, true)
    insert_permission(role.role_id, "user:read", 0, true)
    insert_permission(role.role_id, "user:update", 0, true)
    insert_permission(role.role_id, "dictionary:read", 0, true)
    insert_permission(role.role_id, "notice:read", 0, true)

    user =
      %SysUser{user_id: Identity.v7()}
      |> SysUser.create_changeset(%{
        username: unique("contract_user"),
        password: "Strong!123",
        nickname: "契约用户",
        dept_id: department.dept_id,
        post_id: post.post_id,
        role_id: role.role_id,
        status: 1
      })
      |> Repo.insert!()

    notice =
      %SysNotice{notice_id: Identity.v7()}
      |> SysNotice.changeset(%{
        notice_title: "契约公告",
        notice_type: "notification",
        notice_content: "契约内容",
        status: 1
      })
      |> Ecto.Changeset.change(published: true, publish_at: DateTime.utc_now())
      |> Ecto.Changeset.put_change(:creator_id, user.user_id)
      |> Ecto.Changeset.put_change(:owner_id, user.user_id)
      |> Repo.insert!()

    dict_type =
      %DictType{dict_id: Identity.v7()}
      |> DictType.changeset(%{
        dict_name: "契约状态",
        dict_type: "contract.status",
        status: 1
      })
      |> Repo.insert!()

    dict_data =
      %DictData{dict_code: Identity.v7()}
      |> DictData.changeset(%{
        dict_type: dict_type.dict_type,
        dict_label: "启用",
        dict_value: 1,
        dict_sort: 1,
        is_default: true,
        status: 1
      })
      |> Repo.insert!()

    {:ok, tokens} = Auth.login_plaintext(user.username, "Strong!123")

    %{
      token: tokens.token,
      department: department,
      post: post,
      role: role,
      page_menu: page_menu,
      user: user,
      dict_data: dict_data,
      notice: notice
    }
  end

  defp insert_permission(role_id, permission, menu_type, is_button) do
    menu =
      %SysMenu{}
      |> SysMenu.changeset(%{
        menu_name: permission,
        menu_type: menu_type,
        parent_id: nil,
        is_button: is_button,
        status: 1
      })
      |> Repo.insert!()

    entry =
      Repo.get_by(SysPermission, permission: permission) ||
        Repo.insert!(%SysPermission{
          permission: permission,
          resource: "system",
          domain: permission |> String.split(":") |> Enum.at(1),
          action: permission |> String.split(":") |> List.last(),
          status: 1,
          deprecated: false
        })

    Repo.insert!(%SysRoleMenu{role_id: role_id, menu_id: menu.menu_id})
    Repo.insert!(%SysRolePermission{role_id: role_id, permission_id: entry.permission_id})
    Repo.insert!(%SysMenuPermission{menu_id: menu.menu_id, permission_id: entry.permission_id})
    menu
  end

  defp unique(prefix), do: "#{prefix}_#{System.unique_integer([:positive])}"
end
