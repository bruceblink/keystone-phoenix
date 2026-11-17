defmodule KeystonePhoenix.UserMultiRoleWriteTest do
  use KeystonePhoenix.DataCase, async: false

  import KeystonePhoenix.AdminScopeTestSupport, only: [all_scope_principal: 1]

  alias KeystonePhoenix.Identity
  alias KeystonePhoenix.Repo
  alias KeystonePhoenix.Role
  alias KeystonePhoenix.Role.SysRole
  alias KeystonePhoenix.User
  alias KeystonePhoenix.User.RoleMembership

  test "user roleCodes create and update keep all memberships in sync" do
    first_role = insert_role("multi_create_first")
    second_role = insert_role("multi_create_second")

    assert {:ok, user} =
             User.create_user(
               %{
                 "username" => unique("multi_role_user"),
                 "password" => "Strong!123",
                 "roleCodes" => [first_role.role_key, second_role.role_key]
               },
               authorization: user_authorization("user:create")
             )

    assert user.role_id == first_role.role_id

    assert RoleMembership.list_role_ids_for_user(user.user_id) ==
             Enum.sort([first_role.role_id, second_role.role_id])

    assert {:ok, updated} =
             User.update_user(
               user.user_id,
               %{"roleCodes" => [second_role.role_key]},
               authorization: user_authorization("user:update")
             )

    assert updated.role_id == second_role.role_id
    assert RoleMembership.list_role_ids_for_user(user.user_id) == [second_role.role_id]
  end

  test "null preserves roles, empty roleCodes clears roles, and legacy roleId replaces roles" do
    first_role = insert_role("multi_compat_first")
    second_role = insert_role("multi_compat_second")

    assert {:ok, user} =
             User.create_user(
               %{
                 "username" => unique("multi_compat_user"),
                 "password" => "Strong!123",
                 "roleCodes" => [first_role.role_key, second_role.role_key]
               },
               authorization: user_authorization("user:create")
             )

    assert {:ok, preserved} =
             User.update_user(
               user.user_id,
               %{"nickname" => "保留角色", "roleCodes" => nil},
               authorization: user_authorization("user:update")
             )

    assert preserved.nickname == "保留角色"

    assert RoleMembership.list_role_ids_for_user(user.user_id) ==
             Enum.sort([first_role.role_id, second_role.role_id])

    assert {:ok, cleared} =
             User.update_user(
               user.user_id,
               %{"roleCodes" => []},
               authorization: user_authorization("user:update")
             )

    assert is_nil(cleared.role_id)
    assert RoleMembership.list_role_ids_for_user(user.user_id) == []

    assert {:ok, replaced} =
             User.update_user(
               user.user_id,
               %{"roleId" => first_role.role_id},
               authorization: user_authorization("user:update")
             )

    assert replaced.role_id == first_role.role_id
    assert RoleMembership.list_role_ids_for_user(user.user_id) == [first_role.role_id]
  end

  test "role assignment adds a role and target-role removal keeps other memberships" do
    first_role = insert_role("multi_assign_first")
    second_role = insert_role("multi_assign_second")

    assert {:ok, user} =
             User.create_user(
               %{
                 "username" => unique("multi_assign_user"),
                 "password" => "Strong!123",
                 "roleId" => first_role.role_id
               },
               authorization: user_authorization("user:create")
             )

    assert :ok =
             Role.assign_users(second_role.role_id, [user.user_id],
               authorization: user_authorization("role:assign")
             )

    assert RoleMembership.list_role_ids_for_user(user.user_id) ==
             Enum.sort([first_role.role_id, second_role.role_id])

    assert :ok =
             Role.unassign_users(second_role.role_id, [user.user_id],
               authorization: user_authorization("role:assign")
             )

    assert RoleMembership.list_role_ids_for_user(user.user_id) == [first_role.role_id]
    assert {:ok, remaining} = User.get_user(user.user_id)
    assert remaining.role_id == first_role.role_id
  end

  defp insert_role(prefix) do
    %SysRole{role_id: Identity.v7()}
    |> SysRole.changeset(%{
      role_name: prefix,
      role_key: unique(prefix),
      role_sort: 1,
      data_scope: "ALL",
      status: 1
    })
    |> Repo.insert!()
  end

  defp user_authorization(permission),
    do: %{
      principal:
        all_scope_principal(%{
          permissions: [
            permission,
            "user:create",
            "user:update",
            "role:assign",
            "permission:manage"
          ]
        }),
      permission: permission
    }

  defp unique(prefix), do: "#{prefix}_#{System.unique_integer([:positive])}"
end
