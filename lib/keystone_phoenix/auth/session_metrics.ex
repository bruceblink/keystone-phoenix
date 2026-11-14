defmodule KeystonePhoenix.Auth.SessionMetrics do
  @moduledoc "会话过期清理、活动列表和数量查询。"

  import Ecto.Query

  alias KeystonePhoenix.Auth.{AuthSession, RefreshToken}
  alias KeystonePhoenix.Repo

  @doc "删除绝对到期或空闲到期的会话和刷新令牌。"
  def cleanup_expired do
    now = DateTime.utc_now()

    {count, _} =
      Repo.update_all(
        from(session in AuthSession,
          where:
            (session.active == true or is_nil(session.revoked_at)) and
              (session.refresh_expires_at <= ^now or session.idle_expires_at <= ^now)
        ),
        set: [active: false, revoked_at: now]
      )

    Repo.update_all(
      from(token in RefreshToken,
        where:
          is_nil(token.revoked_at) and (token.expires_at <= ^now or token.idle_expires_at <= ^now)
      ),
      set: [revoked_at: now]
    )

    {:ok, count}
  rescue
    _error -> {:error, :unavailable}
  end

  def list_active do
    now = DateTime.utc_now()

    sessions =
      from(session in AuthSession,
        where:
          session.active == true and is_nil(session.revoked_at) and
            session.refresh_expires_at > ^now and session.idle_expires_at > ^now,
        order_by: [desc: session.inserted_at]
      )
      |> Repo.all()

    {:ok,
     Enum.map(sessions, fn session ->
       %{
         jti: session.jti,
         user_id: session.user_id,
         session_id: session.id,
         refresh_family_id: session.refresh_family_id
       }
     end)}
  rescue
    _error -> {:error, :unavailable}
  end

  def count_active do
    now = DateTime.utc_now()

    count =
      Repo.aggregate(
        from(session in AuthSession,
          where:
            session.active == true and is_nil(session.revoked_at) and
              session.refresh_expires_at > ^now and session.idle_expires_at > ^now
        ),
        :count,
        :id
      )

    {:ok, count}
  rescue
    _error -> {:error, :unavailable}
  end
end
