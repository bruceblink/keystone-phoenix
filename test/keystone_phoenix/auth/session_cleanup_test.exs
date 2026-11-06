defmodule KeystonePhoenix.Auth.SessionCleanupTest do
  use KeystonePhoenix.DataCase, async: false

  alias KeystonePhoenix.Auth.AuthSession
  alias KeystonePhoenix.Auth.Session
  alias KeystonePhoenix.Repo
  alias KeystonePhoenix.User.SysUser

  test "removes expired sessions but keeps active sessions" do
    now = DateTime.utc_now()
    user = insert_user()

    expired =
      Repo.insert!(%AuthSession{
        user_id: user.user_id,
        jti: "expired-#{System.unique_integer([:positive])}",
        expires_at: DateTime.add(now, -60, :second),
        active: false
      })

    active =
      Repo.insert!(%AuthSession{
        user_id: user.user_id,
        jti: "active-#{System.unique_integer([:positive])}",
        expires_at: DateTime.add(now, 60, :second),
        active: true
      })

    assert {:ok, 1} = Session.cleanup_expired()
    refute Repo.get(AuthSession, expired.id)
    assert Repo.get(AuthSession, active.id)
  end

  defp insert_user do
    %SysUser{}
    |> SysUser.create_changeset(%{
      username: "cleanup_#{System.unique_integer([:positive])}",
      password: "Strong!123",
      status: 1
    })
    |> Repo.insert!()
  end
end
