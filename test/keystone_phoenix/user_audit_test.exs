defmodule KeystonePhoenix.UserAuditTest do
  use KeystonePhoenix.DataCase, async: false

  alias KeystonePhoenix.Repo
  alias KeystonePhoenix.User
  alias KeystonePhoenix.User.SysUser

  test "user writes store creator and updater IDs" do
    actor =
      %SysUser{user_id: 1001}
      |> SysUser.create_changeset(%{username: unique("user_actor"), password: "Strong!123"})
      |> Repo.insert!()

    assert {:ok, user} =
             User.create_user(
               %{
                 "username" => unique("managed_user"),
                 "password" => "Strong!123",
                 "nickname" => "被管理用户",
                 "status" => 1
               },
               actor.user_id
             )

    assert user.creator_id == actor.user_id
    assert {:ok, user} = User.update_user(user.user_id, %{"nickname" => "已更新"}, actor.user_id)
    assert user.updater_id == actor.user_id

    assert {:ok, user} =
             User.reset_password(user.user_id, %{"password" => "NewStrong!123"}, actor.user_id)

    assert user.updater_id == actor.user_id
    assert {:ok, user} = User.change_status(user.user_id, 0, actor.user_id)
    assert user.updater_id == actor.user_id

    assert {:ok, another_user} =
             User.create_user(
               %{
                 "username" => unique("deletable_user"),
                 "password" => "Strong!123",
                 "status" => 1
               },
               actor.user_id
             )

    assert :ok = User.delete_users([another_user.user_id], actor.user_id)
    deleted = Repo.get!(SysUser, another_user.user_id)
    assert deleted.deleted
    assert deleted.updater_id == actor.user_id
  end

  defp unique(prefix), do: "#{prefix}_#{System.unique_integer([:positive])}"
end
