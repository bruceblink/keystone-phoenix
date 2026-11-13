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

  @tag :integration
  test "frontend management APIs preserve the expected DTO shapes", %{conn: conn} do
    fixtures = fixtures()
    conn = put_req_header(conn, "authorization", "Bearer #{fixtures.token}")

    assert %{"success" => true, "data" => menus} = json_response(get(conn, "/system/menus"), 200)
    menu = Enum.find(menus, &(&1["id"] == fixtures.page_menu.menu_id))
    assert menu["menuId"] == fixtures.page_menu.menu_id
    assert menu["isButton"] == false
    assert menu["menuTypeStr"] == "页面"
    assert menu["statusStr"] == "正常"

    assert %{"success" => true, "data" => departments} =
             json_response(get(conn, "/system/depts"), 200)

    department = Enum.find(departments, &(&1["id"] == fixtures.department.dept_id))
    assert department["deptId"] == fixtures.department.dept_id
    assert department["statusStr"] == "正常"

    assert %{"success" => true, "data" => %{"rows" => posts}} =
             json_response(get(conn, "/system/post/list?pageSize=50"), 200)

    post = Enum.find(posts, &(&1["postId"] == fixtures.post.post_id))
    assert post["statusStr"] == "正常"

    assert %{"success" => true, "data" => role} =
             json_response(get(conn, "/system/role/#{fixtures.role.role_id}"), 200)

    assert fixtures.page_menu.menu_id in role["selectedMenuList"]
    assert role["selectedDeptList"] == [fixtures.department.dept_id]

    assert %{"success" => true, "data" => %{"rows" => users}} =
             json_response(get(conn, "/system/users?userId=#{fixtures.user.user_id}"), 200)

    user = Enum.find(users, &(&1["userId"] == fixtures.user.user_id))
    assert user["deptName"] == "契约部门"
    assert user["postName"] == "契约岗位"
    assert user["roleName"] == "契约角色"

    assert %{"success" => true, "data" => profile} =
             json_response(get(conn, "/system/user/profile"), 200)

    assert profile["user"]["userId"] == fixtures.user.user_id
    assert profile["roleName"] == "契约角色"
    assert profile["postName"] == "契约岗位"

    assert %{"success" => true, "data" => %{"rows" => dict_data}} =
             json_response(get(conn, "/system/dict/data/list?dictType=contract.status"), 200)

    dict = Enum.find(dict_data, &(&1["dictCode"] == fixtures.dict_data.dict_code))
    assert dict["isDefault"] == 1

    assert %{"success" => true, "data" => %{"rows" => notices}} =
             json_response(get(conn, "/system/notices?pageSize=10"), 200)

    notice = Enum.find(notices, &(&1["noticeId"] == fixtures.notice.notice_id))
    assert notice["creatorName"] == fixtures.user.username
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
        data_scope: 1,
        dept_id_set: department.dept_id,
        status: 1
      })
      |> Repo.insert!()

    page_menu = insert_permission(role.role_id, "menu:read", 1, false)
    insert_permission(role.role_id, "role:read", 0, true)
    insert_permission(role.role_id, "department:read", 0, true)
    insert_permission(role.role_id, "post:read", 0, true)
    insert_permission(role.role_id, "user:read", 0, true)
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
        notice_type: 1,
        notice_content: "契约内容",
        status: 1
      })
      |> Ecto.Changeset.put_change(:creator_id, user.user_id)
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
