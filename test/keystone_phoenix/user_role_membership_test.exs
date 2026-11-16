defmodule KeystonePhoenix.UserRoleMembershipTest do
  use KeystonePhoenix.DataCase, async: false

  import Ecto.Query

  alias KeystonePhoenix.Identity
  alias KeystonePhoenix.Repo
  alias KeystonePhoenix.Role.SysRole
  alias KeystonePhoenix.User.RoleMembership
  alias KeystonePhoenix.User.SysUser
  alias KeystonePhoenix.User.SysUserRole

  test "membership table uses UUID composite keys and backfills the bootstrap role" do
    columns =
      Repo.query!("""
      SELECT column_name, data_type
      FROM information_schema.columns
      WHERE table_schema = current_schema() AND table_name = 'sys_user_role'
      ORDER BY ordinal_position
      """).rows

    assert columns == [["user_id", "uuid"], ["role_id", "uuid"]]

    admin_user_id = Identity.v5(Identity.permission_namespace(), "system:user:admin")
    admin_role_id = Identity.v5(Identity.permission_namespace(), "system:role:admin")

    assert Repo.exists?(
             from membership in SysUserRole,
               where:
                 membership.user_id == ^admin_user_id and
                   membership.role_id == ^admin_role_id
           )
  end

  test "membership schema validates both parts of the composite key" do
    changeset = SysUserRole.changeset(%SysUserRole{}, %{user_id: Identity.v7()})

    refute changeset.valid?
    assert {:role_id, {"can't be blank", _}} = List.keyfind(changeset.errors, :role_id, 0)
  end

  test "membership read boundary returns sorted IDs and rejects invalid input" do
    user_id = Identity.v7()
    role = insert_role()
    other_role = insert_role()
    role_id = role.role_id
    other_role_id = other_role.role_id

    Repo.insert!(%SysUser{
      user_id: user_id,
      username: "membership_user_#{System.unique_integer([:positive])}",
      password: "Strong!123",
      role_id: role_id,
      status: 1
    })

    # 使用真实角色外键写入两条关联，验证查询模块不会依赖旧的 role_id 字段。
    Repo.insert_all(SysUserRole, [
      %{user_id: user_id, role_id: other_role_id},
      %{user_id: user_id, role_id: role_id}
    ])

    assert RoleMembership.list_role_ids_for_user(user_id) == Enum.sort([role_id, other_role_id])
    assert RoleMembership.list_user_ids_for_role(role_id) == [user_id]
    assert RoleMembership.list_role_ids_for_user("not-a-uuid") == []
    assert RoleMembership.list_user_ids_for_role("not-a-uuid") == []
  end

  test "migration source guards replay and checks backfill consistency" do
    migration =
      Path.expand(
        "../../priv/repo/migrations/20261117100000_create_user_role_memberships.exs",
        __DIR__
      )

    source = File.read!(migration)
    assert source =~ "CREATE TABLE IF NOT EXISTS sys_user_role"
    assert source =~ "CREATE INDEX IF NOT EXISTS sys_user_role_role_id_index"
    assert source =~ "ON CONFLICT (user_id, role_id) DO NOTHING"
    assert source =~ "sys_user_role backfill is incomplete"
  end

  test "membership foreign keys point to users and roles" do
    rows =
      Repo.query!("""
      SELECT pg_get_constraintdef(c.oid)
      FROM pg_constraint AS c
      WHERE c.conrelid = 'sys_user_role'::regclass
        AND c.contype = 'f'
      ORDER BY c.conname
      """).rows

    assert Enum.any?(rows, fn [definition] ->
             String.contains?(definition, "(user_id) REFERENCES sys_user(user_id)")
           end)

    assert Enum.any?(rows, fn [definition] ->
             String.contains?(definition, "(role_id) REFERENCES sys_role(role_id)")
           end)
  end

  test "existing bootstrap records remain available after membership backfill" do
    admin_user_id = Identity.v5(Identity.permission_namespace(), "system:user:admin")
    admin_role_id = Identity.v5(Identity.permission_namespace(), "system:role:admin")

    assert %SysUser{role_id: ^admin_role_id} = Repo.get(SysUser, admin_user_id)
    assert %SysRole{role_key: "admin"} = Repo.get(SysRole, admin_role_id)
  end

  defp insert_role do
    %SysRole{}
    |> SysRole.changeset(%{
      role_name: "Membership test role",
      role_key: "membership_test_#{System.unique_integer([:positive])}",
      role_sort: 1,
      status: 1
    })
    |> Repo.insert!()
  end
end
