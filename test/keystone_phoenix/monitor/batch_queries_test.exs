defmodule KeystonePhoenix.Monitor.BatchQueriesTest do
  use KeystonePhoenix.DataCase, async: false

  alias KeystonePhoenix.Department
  alias KeystonePhoenix.Department.SysDept
  alias KeystonePhoenix.Repo
  alias KeystonePhoenix.User
  alias KeystonePhoenix.User.SysUser

  test "batch user and department queries return active records in one boundary" do
    department = Repo.insert!(%SysDept{dept_name: "批量部门", status: 1})

    active_user =
      Repo.insert!(%SysUser{
        username: "batch_active_#{System.unique_integer([:positive])}",
        nickname: "在线用户",
        password: "password-hash",
        dept_id: department.dept_id,
        deleted: false
      })

    deleted_user =
      Repo.insert!(%SysUser{
        username: "batch_deleted_#{System.unique_integer([:positive])}",
        nickname: "已删除用户",
        password: "password-hash",
        dept_id: department.dept_id,
        deleted: true
      })

    users = User.list_users_by_ids([active_user.user_id, deleted_user.user_id, "bad"])
    departments = Department.list_depts_by_ids([department.dept_id, "bad"])

    assert Enum.map(users, & &1.user_id) == [active_user.user_id]
    assert Enum.map(departments, & &1.dept_id) == [department.dept_id]
  end
end
