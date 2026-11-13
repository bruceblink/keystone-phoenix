defmodule KeystonePhoenix.Auth.SessionCleanupTest do
  use KeystonePhoenix.DataCase, async: false

  alias KeystonePhoenix.Auth.AuthSession
  alias KeystonePhoenix.Auth.Session
  alias KeystonePhoenix.Identity
  alias KeystonePhoenix.Repo
  alias KeystonePhoenix.User.SysUser

  test "removes expired sessions but keeps active sessions" do
    now = DateTime.utc_now()
    user = insert_user()

    expired =
      Repo.insert!(%AuthSession{
        id: Identity.v7(),
        user_id: user.user_id,
        client_id: "web",
        jti: Identity.v7(),
        refresh_family_id: Identity.v7(),
        refresh_expires_at: DateTime.add(now, -60, :second),
        idle_expires_at: DateTime.add(now, -60, :second),
        last_seen_at: now,
        expires_at: DateTime.add(now, -60, :second),
        active: false
      })

    active =
      Repo.insert!(%AuthSession{
        id: Identity.v7(),
        user_id: user.user_id,
        client_id: "web",
        jti: Identity.v7(),
        refresh_family_id: Identity.v7(),
        refresh_expires_at: DateTime.add(now, 60, :second),
        idle_expires_at: DateTime.add(now, 60, :second),
        last_seen_at: now,
        expires_at: DateTime.add(now, 60, :second),
        active: true
      })

    assert {:ok, 1} = Session.cleanup_expired()
    assert Repo.get(AuthSession, expired.id).active == false
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
