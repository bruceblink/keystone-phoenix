defmodule KeystonePhoenix.RoleAssignmentTest do
  use KeystonePhoenix.DataCase, async: false

  alias KeystonePhoenix.Repo
  alias KeystonePhoenix.Identity
  alias KeystonePhoenix.Role
  alias KeystonePhoenix.User
  alias KeystonePhoenix.User.SysUser

  test "assigning mixed existing and missing users does not update any user" do
    source_role = create_role()
    target_role = create_role()
    user = create_user(source_role.role_id)
    missing_user_id = missing_user_id()
    before = user_state(user)

    assert {:error, :not_found} =
             Role.assign_users(target_role.role_id, [user.user_id, missing_user_id], admin_auth())

    assert user_state(user) == before
  end

  test "assigning mixed active and soft-deleted users does not update either user" do
    source_role = create_role()
    target_role = create_role()
    active_user = create_user(source_role.role_id)
    deleted_user = create_user(source_role.role_id)
    deleted_user = soft_delete_user(deleted_user)
    active_before = user_state(active_user)
    deleted_before = user_state(deleted_user)

    assert {:error, :not_found} =
             Role.assign_users(
               target_role.role_id,
               [active_user.user_id, deleted_user.user_id],
               admin_auth()
             )

    assert user_state(active_user) == active_before
    assert user_state(deleted_user) == deleted_before
  end

  test "unassigning mixed existing and missing users does not update any user" do
    role = create_role()
    user = create_user(role.role_id)
    missing_user_id = missing_user_id()
    before = user_state(user)

    assert {:error, :not_found} =
             Role.unassign_users([user.user_id, missing_user_id], admin_auth())

    assert user_state(user) == before
  end

  test "unassigning mixed active and soft-deleted users does not update either user" do
    role = create_role()
    active_user = create_user(role.role_id)
    deleted_user = create_user(role.role_id)
    deleted_user = soft_delete_user(deleted_user)
    active_before = user_state(active_user)
    deleted_before = user_state(deleted_user)

    assert {:error, :not_found} =
             Role.unassign_users([active_user.user_id, deleted_user.user_id], admin_auth())

    assert user_state(active_user) == active_before
    assert user_state(deleted_user) == deleted_before
  end

  test "assigning all active users succeeds and ignores duplicate IDs" do
    role = create_role()
    users = [create_user(), create_user()]
    ids = Enum.map(users, & &1.user_id)

    assert :ok = Role.assign_users(role.role_id, ids ++ [hd(ids)], admin_auth())

    for user <- users do
      assert {:ok, updated} = User.get_user(user.user_id)
      assert updated.role_id == role.role_id
    end
  end

  test "unassigning all active users succeeds and ignores duplicate IDs" do
    role = create_role()
    users = [create_user(role.role_id), create_user(role.role_id)]
    ids = Enum.map(users, & &1.user_id)

    assert :ok = Role.unassign_users(ids ++ [hd(ids)], admin_auth())

    for user <- users do
      assert {:ok, updated} = User.get_user(user.user_id)
      assert is_nil(updated.role_id)
    end
  end

  test "assigning one user retains the existing success behavior" do
    role = create_role()
    user = create_user()

    assert :ok = Role.assign_users(role.role_id, [user.user_id], admin_auth())
    assert {:ok, updated} = User.get_user(user.user_id)
    assert updated.role_id == role.role_id
  end

  test "unassigning one user retains the existing success behavior" do
    role = create_role()
    user = create_user(role.role_id)

    assert :ok = Role.unassign_users([user.user_id], admin_auth())
    assert {:ok, updated} = User.get_user(user.user_id)
    assert is_nil(updated.role_id)
  end

  test "assignment rejects disabled and soft-deleted roles without changing the user" do
    disabled_role = create_role(status: 0)
    deleted_role = create_role()

    {:ok, _deleted_role} =
      deleted_role
      |> Ecto.Changeset.change(deleted: true)
      |> Repo.update()

    user = create_user()
    before = user_state(user)

    assert {:error, :role_unavailable} =
             Role.assign_users(disabled_role.role_id, [user.user_id], admin_auth())

    assert {:error, :not_found} =
             Role.assign_users(deleted_role.role_id, [user.user_id], admin_auth())

    assert user_state(user) == before
  end

  test "non-administrators cannot change role assignments" do
    target_role = create_role()
    user = create_user()
    actor = %{permissions: [], role_id: target_role.role_id, user_id: user.user_id}
    before = user_state(user)

    assert {:error, :forbidden} =
             Role.assign_users(target_role.role_id, [user.user_id],
               authorization: %{principal: actor, permission: "role:assign"}
             )

    assert {:error, :forbidden} =
             Role.unassign_users([user.user_id],
               authorization: %{principal: actor, permission: "role:assign"}
             )

    assert user_state(user) == before
  end

  test "role user lists use the actor data scope" do
    role = create_role()
    actor_role = create_role(data_scope: "SELF")
    actor = create_user(actor_role.role_id)
    assigned_to_role = create_user(role.role_id)

    rows = Role.list_allocated_users(role.role_id, %{"pageSize" => 50}, actor)

    refute assigned_to_role.user_id in Enum.map(rows.rows, & &1["userId"])
    assert rows.total == 0
  end

  defp create_role(opts \\ []) do
    attrs = %{
      "roleName" => "角色分配测试",
      "roleKey" => unique("role_assignment"),
      "roleSort" => 1,
      "dataScope" => Keyword.get(opts, :data_scope, "ALL"),
      "status" => Keyword.get(opts, :status, 1),
      "menuIds" => []
    }

    {:ok, role} = Role.create_role(attrs, admin_auth("role:create"))
    role
  end

  defp admin_auth(permission \\ "role:assign"),
    do: [
      authorization: %{
        principal: %{permissions: [permission, "permission:manage"]},
        permission: permission
      }
    ]

  defp create_user(role_id \\ nil) do
    attrs = %{
      "username" => unique("role_assignment_user"),
      "password" => "Strong!123"
    }

    attrs = if is_nil(role_id), do: attrs, else: Map.put(attrs, "roleId", role_id)

    {:ok, user} =
      User.create_user(attrs,
        authorization: %{
          principal: %{permissions: ["user:create", "role:assign", "permission:manage"]},
          permission: "user:create"
        }
      )

    user
  end

  defp soft_delete_user(user) do
    {:ok, deleted_user} =
      user
      |> Ecto.Changeset.change(deleted: true)
      |> Repo.update()

    deleted_user
  end

  defp user_state(user) do
    user = Repo.get!(SysUser, user.user_id)
    %{deleted: user.deleted, role_id: user.role_id, update_time: user.update_time}
  end

  defp missing_user_id do
    id = Identity.v7()
    assert is_nil(Repo.get(SysUser, id))
    id
  end

  defp unique(prefix), do: "#{prefix}_#{System.unique_integer([:positive])}"
end
