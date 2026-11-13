defmodule KeystonePhoenix.IdentityCoreTest do
  use KeystonePhoenix.DataCase, async: true

  alias KeystonePhoenix.Department.SysDept
  alias KeystonePhoenix.Identity
  alias KeystonePhoenix.Params
  alias KeystonePhoenix.Authz.SysRolePermission
  alias KeystonePhoenix.Role.SysRole
  alias KeystonePhoenix.User.SysUser

  test "accepts only canonical UUID strings at the request boundary" do
    uuid = Identity.v7()

    assert {:ok, ^uuid} = Params.parse_uuid(uuid)
    assert :error = Params.parse_uuid(String.upcase(uuid))
    assert :error = Params.parse_uuid(42)
  end

  test "core changesets generate UUIDv7 identifiers" do
    user = SysUser.create_changeset(%SysUser{}, %{username: "uuid-user", password: "P@ssword123"})

    role =
      SysRole.changeset(%SysRole{}, %{role_name: "UUID Role", role_key: "uuid-role", role_sort: 1})

    dept =
      SysDept.changeset(%SysDept{}, %{dept_name: "UUID Department", status: 1, parent_id: nil})

    assert {:ok, user_id} = Ecto.Changeset.get_change(user, :user_id) |> Params.parse_uuid()
    assert {:ok, role_id} = Ecto.Changeset.get_change(role, :role_id) |> Params.parse_uuid()
    assert {:ok, dept_id} = Ecto.Changeset.get_change(dept, :dept_id) |> Params.parse_uuid()
    assert Identity.canonical?(user_id)
    assert Identity.canonical?(role_id)
    assert Identity.canonical?(dept_id)
    assert Ecto.Changeset.get_field(dept, :parent_id) == nil
  end

  test "uuid migration leaves the minimum bootstrap authorization records" do
    namespace = Identity.permission_namespace()
    root_dept_id = Identity.v5(namespace, "system:department:root")
    admin_role_id = Identity.v5(namespace, "system:role:admin")
    admin_user_id = Identity.v5(namespace, "system:user:admin")
    permission_manage_id = Identity.permission_id("permission:manage")

    assert %SysDept{parent_id: nil} = Repo.get(SysDept, root_dept_id)
    assert %SysRole{role_key: "admin"} = Repo.get(SysRole, admin_role_id)

    assert %SysUser{role_id: ^admin_role_id, dept_id: ^root_dept_id} =
             Repo.get(SysUser, admin_user_id)

    assert Repo.exists?(
             from binding in SysRolePermission,
               where:
                 binding.role_id == ^admin_role_id and
                   binding.permission_id == ^permission_manage_id
           )
  end

  test "administrator capability has no user table bypass column" do
    %{rows: [[count]]} =
      Repo.query!("""
      SELECT COUNT(*)
      FROM information_schema.columns
      WHERE table_schema = current_schema()
        AND table_name = 'sys_user'
        AND column_name = 'is_admin'
      """)

    assert count == 0
  end
end
