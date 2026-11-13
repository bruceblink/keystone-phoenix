defmodule KeystonePhoenix.AuthTest do
  use KeystonePhoenix.DataCase, async: false

  alias KeystonePhoenix.Auth
  alias KeystonePhoenix.Cache
  alias KeystonePhoenix.Config.SysConfig
  alias KeystonePhoenix.User.SysUser

  setup do
    Cache.delete_prefix("keystone:system:config:")

    _captcha_config =
      Repo.get_by(SysConfig, config_key: "sys.account.captchaOnOff", deleted: false) ||
        %SysConfig{}
        |> SysConfig.changeset(%{
          config_name: "验证码开关",
          config_key: "sys.account.captchaOnOff",
          config_value: "false",
          is_allow_change: true
        })
        |> Repo.insert!()

    user =
      %SysUser{}
      |> SysUser.create_changeset(%{
        username: "auth_#{System.unique_integer([:positive])}",
        password: "Strong!123",
        status: 1
      })
      |> Repo.insert!()

    on_exit(fn -> Cache.delete_prefix("keystone:system:config:") end)

    {:ok, user: user}
  end

  test "handles first, repeated, and forced login without reviving the old session", %{
    user: user
  } do
    assert {:ok, first} = Auth.login_plaintext(user.username, "Strong!123")
    assert {:error, :already_logged_in} = Auth.login_plaintext(user.username, "Strong!123")

    assert {:ok, forced} = Auth.login_plaintext(user.username, "Strong!123", true)
    assert {:error, :invalid_token} = Auth.authenticate_access_token(first.token)
    assert {:ok, _current_user} = Auth.authenticate_access_token(forced.token)
  end

  test "rotates refresh sessions and rejects replay after logout", %{user: user} do
    assert {:ok, first} = Auth.login_plaintext(user.username, "Strong!123")
    assert {:ok, rotated} = Auth.refresh(first.refresh_token)
    assert {:error, :invalid_refresh_token} = Auth.refresh(first.refresh_token)
    assert {:ok, _current_user} = Auth.authenticate_access_token(rotated.token)

    assert :ok = Auth.logout(rotated.refresh_token)
    assert {:error, :invalid_refresh_token} = Auth.refresh(rotated.refresh_token)
  end

  test "supports users without a role when building the login response" do
    user =
      %SysUser{}
      |> SysUser.create_changeset(%{
        username: "no_role_#{System.unique_integer([:positive])}",
        password: "Strong!123",
        status: 1
      })
      |> Repo.insert!()

    assert {:ok, tokens} = Auth.login_plaintext(user.username, "Strong!123")
    assert tokens.current_user["roleKey"] == ""
    assert tokens.current_user["permissions"] == []
  end

  test "increments permission version when user authorization state changes", %{user: user} do
    assert user.permission_version == 1

    assert {:ok, updated} =
             KeystonePhoenix.User.update_user(
               user.user_id,
               %{"status" => 0},
               authorization: %{
                 principal: %{
                   user_id: user.user_id,
                   permissions: ["permission:manage", "user:update"]
                 },
                 permission: "user:update"
               }
             )

    assert updated.permission_version == 2
  end
end
