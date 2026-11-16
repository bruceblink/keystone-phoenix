defmodule KeystonePhoenixWeb.AdminEventsAccountsScopeTest do
  use KeystonePhoenix.DataCase, async: false

  alias KeystonePhoenix.Repo
  alias KeystonePhoenix.Role.SysRole
  alias KeystonePhoenix.User.SysUser
  alias KeystonePhoenixWeb.Live.AdminEvents.Accounts
  alias KeystonePhoenixWeb.Live.AdminEventsAccountsParams
  alias KeystonePhoenixWeb.Live.AdminPages.Feedback

  test "user edit permission still respects the actor role data scope" do
    actor_dept =
      Repo.insert!(%KeystonePhoenix.Department.SysDept{
        dept_id: Ecto.UUID.generate(),
        dept_name: unique("actor_dept"),
        parent_id: nil,
        ancestors: "",
        status: 1
      })

    target_dept =
      Repo.insert!(%KeystonePhoenix.Department.SysDept{
        dept_id: Ecto.UUID.generate(),
        dept_name: unique("target_dept"),
        parent_id: nil,
        ancestors: "",
        status: 1
      })

    role =
      Repo.insert!(%SysRole{
        role_id: Ecto.UUID.generate(),
        role_name: unique("scope_role"),
        role_key: unique("scope_role"),
        role_sort: 1,
        data_scope: "DEPARTMENT",
        status: 1
      })

    actor =
      Repo.insert!(%SysUser{
        user_id: Ecto.UUID.generate(),
        username: unique("scope_actor"),
        password: "password-hash",
        role_id: role.role_id,
        dept_id: actor_dept.dept_id,
        status: 1
      })

    target =
      Repo.insert!(%SysUser{
        user_id: Ecto.UUID.generate(),
        username: unique("scope_target"),
        password: "password-hash",
        dept_id: target_dept.dept_id,
        status: 1,
        nickname: "原昵称"
      })

    socket = %Phoenix.LiveView.Socket{
      assigns: %{
        __changed__: %{},
        current_user: %{
          "userId" => actor.user_id,
          "roleId" => role.role_id,
          "deptId" => actor_dept.dept_id
        },
        permissions: ["user:update"]
      }
    }

    assert {:noreply, updated_socket} =
             Accounts.handle_event(
               "save-user",
               %{
                 "userId" => to_string(target.user_id),
                 "username" => target.username,
                 "nickname" => "不应保存"
               },
               socket
             )

    assert updated_socket.assigns.user_feedback ==
             Feedback.error(:data_scope_denied, "没有数据权限")

    assert Repo.get!(SysUser, target.user_id).nickname == "原昵称"
  end

  test "user form normalizes multiple, empty, and null role codes" do
    first_role =
      Repo.insert!(%SysRole{
        role_id: Ecto.UUID.generate(),
        role_name: unique("role_code_first"),
        role_key: unique("role_code_first_key"),
        role_sort: 1,
        data_scope: "ALL",
        status: 1
      })

    second_role =
      Repo.insert!(%SysRole{
        role_id: Ecto.UUID.generate(),
        role_name: unique("role_code_second"),
        role_key: unique("role_code_second_key"),
        role_sort: 1,
        data_scope: "ALL",
        status: 1
      })

    assert {:ok, %{"roleCodes" => codes}} =
             AdminEventsAccountsParams.normalize_user_params(%{
               "roleCodes" =>
                 " #{first_role.role_key}, #{second_role.role_key}, #{first_role.role_key} "
             })

    assert codes == [first_role.role_key, second_role.role_key, first_role.role_key]

    assert {:ok, %{"roleCodes" => []}} =
             AdminEventsAccountsParams.normalize_user_params(%{"roleCodes" => []})

    assert {:ok, %{"roleCodes" => nil}} =
             AdminEventsAccountsParams.normalize_user_params(%{"roleCodes" => nil})
  end

  defp unique(prefix), do: "#{prefix}_#{System.unique_integer([:positive])}"
end
