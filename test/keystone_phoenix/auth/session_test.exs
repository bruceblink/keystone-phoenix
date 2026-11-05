defmodule KeystonePhoenix.Auth.SessionTest do
  use KeystonePhoenix.DataCase, async: false

  alias KeystonePhoenix.Auth.Session
  alias KeystonePhoenix.Repo
  alias KeystonePhoenix.User.SysUser

  setup do
    user =
      Repo.insert!(%SysUser{
        username: "session_#{System.unique_integer([:positive])}",
        password: "password-hash",
        status: 1
      })

    {:ok, user: user}
  end

  test "persists and revokes a refresh session", %{user: user} do
    jti = "session-#{System.unique_integer([:positive])}"

    assert :ok = Session.occupy(user.user_id, jti, 600)
    assert Session.valid?(jti, user.user_id)
    assert Session.active?(user.user_id, jti)
    assert {:ok, [%{jti: ^jti, user_id: user_id}]} = Session.list_active()
    assert user_id == user.user_id

    assert :ok = Session.revoke_token(jti)
    refute Session.valid?(jti, user.user_id)
    assert {:error, :not_found} = Session.revoke_token(jti)
  end

  test "force login replaces the previous active session", %{user: user} do
    first_jti = "first-#{System.unique_integer([:positive])}"
    second_jti = "second-#{System.unique_integer([:positive])}"

    assert :ok = Session.occupy(user.user_id, first_jti, 600)
    assert {:error, :already_logged_in} = Session.occupy(user.user_id, second_jti, 600)
    assert :ok = Session.occupy(user.user_id, second_jti, 600, true)
    refute Session.active?(user.user_id, first_jti)
    assert Session.active?(user.user_id, second_jti)
  end
end
