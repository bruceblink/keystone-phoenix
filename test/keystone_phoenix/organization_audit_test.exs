defmodule KeystonePhoenix.OrganizationAuditTest do
  use KeystonePhoenix.DataCase, async: false

  alias KeystonePhoenix.Department
  alias KeystonePhoenix.Menu
  alias KeystonePhoenix.Post
  alias KeystonePhoenix.Repo
  alias KeystonePhoenix.Role
  alias KeystonePhoenix.User.SysUser

  test "organization writes store the authenticated actor" do
    actor =
      %SysUser{user_id: 901}
      |> SysUser.create_changeset(%{
        username: unique("organization_actor"),
        password: "Strong!123"
      })
      |> Repo.insert!()

    assert {:ok, department} =
             Department.create_dept(
               %{"deptName" => "审计部门", "status" => 1},
               authorization: %{principal: %{user_id: actor.user_id, is_admin: true}}
             )

    assert department.creator_id == actor.user_id

    assert {:ok, department} =
             Department.update_dept(
               department.dept_id,
               %{"status" => 0},
               authorization: %{principal: %{user_id: actor.user_id, is_admin: true}}
             )

    assert department.updater_id == actor.user_id

    assert {:ok, post} =
             Post.create_post(
               %{
                 "postCode" => unique("audit_post"),
                 "postName" => "审计岗位",
                 "postSort" => 1,
                 "status" => 1
               },
               authorization: %{principal: %{user_id: actor.user_id, is_admin: true}}
             )

    assert post.creator_id == actor.user_id

    assert {:ok, post} =
             Post.update_post(
               post.post_id,
               %{"status" => 0},
               authorization: %{principal: %{user_id: actor.user_id, is_admin: true}}
             )

    assert post.updater_id == actor.user_id

    assert {:ok, menu} =
             Menu.create_menu(
               %{"menuName" => "审计菜单", "menuType" => 1, "parentId" => 0, "status" => 1},
               authorization: %{
                 principal: %{user_id: actor.user_id, is_admin: true},
                 permission: "system:menu:add"
               }
             )

    assert menu.creator_id == actor.user_id

    assert {:ok, menu} =
             Menu.update_menu(menu.menu_id, %{"status" => 0},
               authorization: %{
                 principal: %{user_id: actor.user_id, is_admin: true},
                 permission: "system:menu:edit"
               }
             )

    assert menu.updater_id == actor.user_id

    assert {:ok, role} =
             Role.create_role(
               %{
                 "roleName" => "审计角色",
                 "roleKey" => unique("audit_role"),
                 "roleSort" => 1,
                 "dataScope" => 1,
                 "status" => 1,
                 "menuIds" => []
               },
               authorization: %{
                 principal: %{user_id: actor.user_id, is_admin: true},
                 permission: "system:role:add"
               }
             )

    assert role.creator_id == actor.user_id

    assert {:ok, role} =
             Role.update_role(role.role_id, %{"roleName" => "更新角色"},
               authorization: %{
                 principal: %{user_id: actor.user_id, is_admin: true},
                 permission: "system:role:edit"
               }
             )

    assert role.updater_id == actor.user_id
  end

  test "principal-aware department and post writes reject missing permissions" do
    authorization = %{principal: %{user_id: 903, permissions: []}}

    assert {:error, :permission_denied} =
             Department.create_dept(%{"deptName" => "受保护部门"}, authorization: authorization)

    assert {:error, :permission_denied} =
             Post.create_post(
               %{"postCode" => unique("protected_post"), "postName" => "受保护岗位"},
               authorization: authorization
             )
  end

  defp unique(prefix), do: "#{prefix}_#{System.unique_integer([:positive])}"
end
