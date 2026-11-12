defmodule KeystonePhoenix.OrganizationTreeTest do
  use KeystonePhoenix.DataCase, async: false

  alias KeystonePhoenix.Department
  alias KeystonePhoenix.Department.SysDept
  alias KeystonePhoenix.Menu
  alias KeystonePhoenix.Menu.SysMenu
  alias KeystonePhoenix.Post
  alias KeystonePhoenix.Post.SysPost
  alias KeystonePhoenix.Repo
  alias KeystonePhoenix.Role.{SysRole, SysRoleMenu}

  test "department moves recompute descendants and reject invalid parents" do
    old_parent = insert_dept(201, 0, "0", "旧部门")
    new_parent = insert_dept(202, 0, "0", "新部门")
    child = insert_dept(203, old_parent.dept_id, "0,201", "子部门")
    grandchild = insert_dept(204, child.dept_id, "0,201,203", "孙部门")

    assert {:ok, _updated} =
             Department.update_dept(old_parent.dept_id, %{"parentId" => new_parent.dept_id},
               authorization: %{principal: %{is_admin: true}}
             )

    assert {:ok, moved} = Department.get_dept(old_parent.dept_id)
    assert {:ok, moved_child} = Department.get_dept(child.dept_id)
    assert {:ok, moved_grandchild} = Department.get_dept(grandchild.dept_id)
    assert moved.ancestors == "0,202"
    assert moved_child.ancestors == "0,202,201"
    assert moved_grandchild.ancestors == "0,202,201,203"

    assert {:error, :invalid_parent} =
             Department.update_dept(old_parent.dept_id, %{"parentId" => child.dept_id},
               authorization: %{principal: %{is_admin: true}}
             )

    assert {:error, :name_exists} =
             Department.create_dept(
               %{
                 "parentId" => old_parent.dept_id,
                 "deptName" => "子部门",
                 "status" => 1
               },
               authorization: %{principal: %{is_admin: true}}
             )

    disabled = insert_dept(205, 0, "0", "停用部门", 0)

    assert {:error, :parent_disabled} =
             Department.create_dept(
               %{
                 "parentId" => disabled.dept_id,
                 "deptName" => "非法子部门",
                 "status" => 1
               },
               authorization: %{principal: %{is_admin: true}}
             )

    assert {:error, :status_invalid} =
             Department.update_dept(new_parent.dept_id, %{"status" => 0},
               authorization: %{principal: %{is_admin: true}}
             )
  end

  test "menu rules prevent invalid trees and deleting assigned menus" do
    root = insert_menu(301, 0, 2, false, "目录")
    page = insert_menu(302, root.menu_id, 1, false, "页面")

    assert {:error, :invalid_parent} =
             Menu.update_menu(root.menu_id, %{"parentId" => page.menu_id},
               authorization: %{principal: %{is_admin: true}, permission: "system:menu:edit"}
             )

    assert {:error, :menu_type_locked} =
             Menu.update_menu(page.menu_id, %{"menuType" => 2},
               authorization: %{principal: %{is_admin: true}, permission: "system:menu:edit"}
             )

    assert {:error, :menu_parent_invalid} =
             Menu.create_menu(
               %{
                 "parentId" => page.menu_id,
                 "menuName" => "嵌套页面",
                 "menuType" => 1,
                 "status" => 1
               },
               authorization: %{principal: %{is_admin: true}, permission: "system:menu:add"}
             )

    assert {:error, :external_link_invalid} =
             Menu.create_menu(
               %{
                 "parentId" => 0,
                 "menuName" => "外链",
                 "menuType" => 4,
                 "path" => "javascript:alert(1)",
                 "status" => 1
               },
               authorization: %{principal: %{is_admin: true}, permission: "system:menu:add"}
             )

    assert {:error, :external_link_invalid} =
             Menu.create_menu(
               %{
                 "parentId" => 0,
                 "menuName" => "相对外链",
                 "menuType" => 4,
                 "path" => "https:relative",
                 "status" => 1
               },
               authorization: %{principal: %{is_admin: true}, permission: "system:menu:add"}
             )

    role =
      %SysRole{}
      |> SysRole.changeset(%{
        role_name: "菜单角色",
        role_key: unique("menu_role"),
        role_sort: 1,
        data_scope: 1,
        status: 1
      })
      |> Repo.insert!()

    Repo.insert!(%SysRoleMenu{role_id: role.role_id, menu_id: page.menu_id})

    assert {:error, :assigned_to_role} =
             Menu.delete_menu(page.menu_id,
               authorization: %{principal: %{is_admin: true}, permission: "system:menu:remove"}
             )
  end

  test "menu maps expose the frontend tree contract and button filter" do
    page =
      %SysMenu{menu_id: 401}
      |> SysMenu.changeset(%{
        parent_id: 0,
        menu_name: "前端页面",
        menu_type: 1,
        is_button: false,
        meta_info: ~s({"rank":5,"icon":"ri-home-line"}),
        path: "/home",
        status: 1
      })
      |> Repo.insert!()

    button = insert_menu(402, 0, 0, true, "前端按钮")
    rows = Menu.list_menus()
    page_row = Enum.find(rows, &(&1["menuId"] == page.menu_id))
    button_row = Enum.find(rows, &(&1["menuId"] == button.menu_id))

    assert page_row["id"] == page.menu_id
    assert page_row["isButton"] == false
    assert page_row["menuType"] == 1
    assert page_row["menuTypeStr"] == "页面"
    assert page_row["statusStr"] == "正常"
    assert page_row["rank"] == 5
    assert page_row["icon"] == "ri-home-line"
    assert Enum.map(Menu.list_menus(%{"isButton" => "false"}), & &1["menuId"]) == [page.menu_id]
    assert button_row["id"] == button.menu_id
    assert button_row["isButton"] == true
    assert button_row["menuType"] == 0
    assert button_row["menuTypeStr"] == "按钮"
  end

  test "department and post maps expose frontend identifiers and labels" do
    dept = insert_dept(403, 0, "0", "前端部门")

    assert %{
             "id" => 403,
             "deptId" => 403,
             "statusStr" => "正常"
           } = Department.dept_to_map(dept)

    assert [%{"id" => 403, "deptName" => "前端部门"}] = Department.list_dropdown()

    post =
      %SysPost{post_id: 404}
      |> SysPost.changeset(%{
        post_code: "frontend_post",
        post_name: "前端岗位",
        post_sort: 1,
        status: 0
      })
      |> Repo.insert!()

    assert Post.post_to_map(post)["statusStr"] == "停用"
  end

  defp insert_dept(id, parent_id, ancestors, name, status \\ 1) do
    %SysDept{dept_id: id}
    |> SysDept.changeset(%{
      parent_id: parent_id,
      ancestors: ancestors,
      dept_name: name,
      status: status
    })
    |> Repo.insert!()
  end

  defp insert_menu(id, parent_id, menu_type, is_button, name) do
    %SysMenu{menu_id: id}
    |> SysMenu.changeset(%{
      parent_id: parent_id,
      menu_name: name,
      menu_type: menu_type,
      is_button: is_button,
      path: "/#{id}",
      status: 1
    })
    |> Repo.insert!()
  end

  defp unique(prefix), do: "#{prefix}_#{System.unique_integer([:positive])}"
end
