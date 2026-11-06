defmodule KeystonePhoenix.UserContractTest do
  use KeystonePhoenix.DataCase, async: false

  alias KeystonePhoenix.Department.SysDept
  alias KeystonePhoenix.Post.SysPost
  alias KeystonePhoenix.Repo
  alias KeystonePhoenix.Role.SysRole
  alias KeystonePhoenix.User
  alias KeystonePhoenix.User.SysUser

  test "user rows and profile include related display names" do
    dept =
      %SysDept{dept_id: 501}
      |> SysDept.changeset(%{dept_name: "合同部门", ancestors: "0", status: 1})
      |> Repo.insert!()

    post =
      %SysPost{post_id: 502}
      |> SysPost.changeset(%{
        post_code: "contract_post",
        post_name: "合同岗位",
        post_sort: 1,
        status: 1
      })
      |> Repo.insert!()

    role =
      %SysRole{role_id: 503}
      |> SysRole.changeset(%{
        role_name: "合同角色",
        role_key: unique("contract_role"),
        role_sort: 1,
        data_scope: 1,
        status: 1
      })
      |> Repo.insert!()

    user =
      %SysUser{user_id: 504}
      |> SysUser.create_changeset(%{
        username: unique("contract_user"),
        password: "Strong!123",
        nickname: "合同用户",
        dept_id: dept.dept_id,
        post_id: post.post_id,
        role_id: role.role_id,
        status: 1
      })
      |> Repo.insert!()

    assert %{rows: [row]} = User.list_users(%{"userId" => user.user_id})
    assert row["deptName"] == "合同部门"
    assert row["postName"] == "合同岗位"
    assert row["roleName"] == "合同角色"

    assert {:ok, profile} = User.profile(user.user_id)
    assert profile["user"]["userId"] == user.user_id
    assert profile["roleName"] == "合同角色"
    assert profile["postName"] == "合同岗位"
  end

  defp unique(prefix), do: "#{prefix}_#{System.unique_integer([:positive])}"
end
