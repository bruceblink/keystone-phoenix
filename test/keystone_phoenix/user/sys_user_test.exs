defmodule KeystonePhoenix.User.SysUserTest do
  use ExUnit.Case, async: true

  alias KeystonePhoenix.User.SysUser

  test "create changeset validates and hashes a strong password" do
    changeset =
      SysUser.create_changeset(%SysUser{}, %{
        "username" => "new_user",
        "nickname" => "新用户",
        "password" => "Strong!123",
        "status" => 1
      })

    assert changeset.valid?
    assert Bcrypt.verify_pass("Strong!123", changeset.changes.password)
    refute changeset.changes.password == "Strong!123"
  end

  test "create changeset rejects weak passwords and invalid usernames" do
    changeset =
      SysUser.create_changeset(%SysUser{}, %{
        "username" => "1-invalid",
        "password" => "123456",
        "status" => 1
      })

    refute changeset.valid?
    assert Keyword.has_key?(changeset.errors, :username)
    assert Keyword.has_key?(changeset.errors, :password)
  end

  test "update changeset does not accept a plaintext password field" do
    user = %SysUser{user_id: 7, username: "admin", password: "existing-hash"}
    changeset = SysUser.update_changeset(user, %{"password" => "Strong!123", "nickname" => "管理员"})

    assert changeset.valid?
    refute Map.has_key?(changeset.changes, :password)
    assert changeset.changes.nickname == "管理员"
  end
end
