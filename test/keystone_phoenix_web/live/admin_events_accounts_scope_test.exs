defmodule KeystonePhoenixWeb.AdminEventsAccountsScopeTest do
  use KeystonePhoenix.DataCase, async: false

  alias KeystonePhoenix.Repo
  alias KeystonePhoenix.Role.SysRole
  alias KeystonePhoenix.User.SysUser
  alias KeystonePhoenixWeb.Live.AdminEvents.Accounts

  test "user edit permission still respects the actor role data scope" do
    actor_dept =
      Repo.insert!(%KeystonePhoenix.Department.SysDept{
        dept_name: unique("actor_dept"),
        parent_id: 0,
        ancestors: "0",
        status: 1
      })

    target_dept =
      Repo.insert!(%KeystonePhoenix.Department.SysDept{
        dept_name: unique("target_dept"),
        parent_id: 0,
        ancestors: "0",
        status: 1
      })

    role =
      Repo.insert!(%SysRole{
        role_name: unique("scope_role"),
        role_key: unique("scope_role"),
        role_sort: 1,
        data_scope: 3,
        status: 1
      })

    actor =
      Repo.insert!(%SysUser{
        username: unique("scope_actor"),
        password: "password-hash",
        role_id: role.role_id,
        dept_id: actor_dept.dept_id,
        status: 1
      })

    target =
      Repo.insert!(%SysUser{
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

    assert updated_socket.assigns.user_feedback == {:error, "没有数据权限"}
    assert Repo.get!(SysUser, target.user_id).nickname == "原昵称"
  end

  defp unique(prefix), do: "#{prefix}_#{System.unique_integer([:positive])}"
end
