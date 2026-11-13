defmodule KeystonePhoenix.OrganizationAuditTest do
  use KeystonePhoenix.DataCase, async: false

  alias KeystonePhoenix.Department
  alias KeystonePhoenix.Identity
  alias KeystonePhoenix.Menu
  alias KeystonePhoenix.Post
  alias KeystonePhoenix.Repo
  alias KeystonePhoenix.Role
  alias KeystonePhoenix.User.SysUser

  test "organization writes store the authenticated actor" do
    actor =
      %SysUser{user_id: Identity.v7()}
      |> SysUser.create_changeset(%{
        username: unique("organization_actor"),
        password: "Strong!123"
      })
      |> Repo.insert!()

    assert {:ok, department} =
             Department.create_dept(
               %{"deptName" => "审计部门", "status" => 1},
               authorization: authorization(actor)
             )

    assert department.creator_id == actor.user_id

    assert {:ok, department} =
             Department.update_dept(
               department.dept_id,
               %{"status" => 0},
               authorization: authorization(actor)
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
               authorization: authorization(actor)
             )

    assert post.creator_id == actor.user_id

    assert {:ok, post} =
             Post.update_post(
               post.post_id,
               %{"status" => 0},
               authorization: authorization(actor)
             )

    assert post.updater_id == actor.user_id

    assert {:ok, menu} =
             Menu.create_menu(
               %{"menuName" => "审计菜单", "menuType" => 1, "parentId" => nil, "status" => 1},
               authorization: authorization(actor, "menu:create")
             )

    assert menu.creator_id == actor.user_id

    assert {:ok, menu} =
             Menu.update_menu(menu.menu_id, %{"status" => 0},
               authorization: authorization(actor, "menu:update")
             )

    assert menu.updater_id == actor.user_id

    assert {:ok, role} =
             Role.create_role(
               %{
                 "roleName" => "审计角色",
                 "roleKey" => unique("audit_role"),
                 "roleSort" => 1,
                 "dataScope" => "ALL",
                 "status" => 1,
                 "menuIds" => []
               },
               authorization: authorization(actor, "role:create")
             )

    assert role.creator_id == actor.user_id

    assert {:ok, role} =
             Role.update_role(role.role_id, %{"roleName" => "更新角色"},
               authorization: authorization(actor, "role:update")
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

  defp authorization(actor, permission \\ nil) do
    permissions = [
      "permission:manage",
      "department:create",
      "department:update",
      "post:create",
      "post:update",
      "menu:create",
      "menu:update",
      "role:create",
      "role:update"
    ]

    %{principal: %{user_id: actor.user_id, permissions: permissions}, permission: permission}
    |> Map.update!(:permission, &(&1 || "permission:manage"))
  end
end
