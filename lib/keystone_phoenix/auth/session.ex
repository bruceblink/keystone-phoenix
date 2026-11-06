defmodule KeystonePhoenix.Auth.Session do
  @moduledoc "PostgreSQL-backed refresh token sessions."

  import Ecto.Query

  alias KeystonePhoenix.Auth.AuthSession
  alias KeystonePhoenix.Repo

  @doc "Claims the only active refresh session allowed for a user."
  @spec occupy(integer(), String.t(), pos_integer(), boolean()) :: :ok | {:error, atom()}
  def occupy(user_id, jti, ttl, force_login \\ false) do
    now = DateTime.utc_now()
    expires_at = DateTime.add(now, ttl, :second)

    Repo.transaction(fn ->
      lock_user(user_id)
      expire_user_sessions(user_id, now)

      case active_session(user_id, now) do
        nil ->
          activate_session(user_id, jti, expires_at)

        %{jti: ^jti} ->
          activate_session(user_id, jti, expires_at)

        _session when force_login ->
          revoke_user_sessions(user_id)
          activate_session(user_id, jti, expires_at)

        _session ->
          Repo.rollback(:already_logged_in)
      end
    end)
    |> occupy_result()
  rescue
    _error -> {:error, :unavailable}
  end

  @doc "Checks whether a refresh token belongs to an active user session."
  @spec valid?(String.t(), integer()) :: boolean()
  def valid?(jti, user_id) do
    now = DateTime.utc_now()

    Repo.exists?(
      from(session in AuthSession,
        where:
          session.jti == ^jti and session.user_id == ^user_id and session.active == true and
            is_nil(session.revoked_at) and session.expires_at > ^now
      )
    )
  rescue
    _error -> false
  end

  @doc "Checks whether a token is the current active session for a user."
  @spec active?(integer(), String.t()) :: boolean()
  def active?(user_id, jti), do: valid?(jti, user_id)

  @doc "Revokes a user's current session."
  @spec release(integer(), String.t()) :: :ok
  def release(user_id, jti) do
    Repo.delete_all(
      from(session in AuthSession, where: session.user_id == ^user_id and session.jti == ^jti)
    )

    :ok
  rescue
    _error -> :ok
  end

  @spec revoke(integer(), String.t()) :: :ok
  def revoke(user_id, jti), do: release(user_id, jti)

  @doc "Revokes the refresh session currently associated with a user account."
  @spec revoke_account(integer()) :: :ok
  def revoke_account(user_id) do
    Repo.delete_all(from(session in AuthSession, where: session.user_id == ^user_id))

    :ok
  rescue
    _error -> :ok
  end

  @doc "Removes a refresh session by its token identifier."
  @spec delete(String.t()) :: :ok
  def delete(jti) do
    Repo.delete_all(from(session in AuthSession, where: session.jti == ^jti))
    :ok
  rescue
    _error -> :ok
  end

  @doc "Deletes expired refresh sessions and returns the number removed."
  @spec cleanup_expired() :: {:ok, non_neg_integer()} | {:error, :unavailable}
  def cleanup_expired do
    {count, _} =
      Repo.delete_all(
        from(session in AuthSession, where: session.expires_at <= ^DateTime.utc_now())
      )

    {:ok, count}
  rescue
    _error -> {:error, :unavailable}
  end

  @doc "Returns active refresh sessions from PostgreSQL."
  @spec list_active() :: {:ok, list(map())} | {:error, :unavailable}
  def list_active do
    now = DateTime.utc_now()

    Repo.delete_all(from(session in AuthSession, where: session.expires_at <= ^now))

    sessions =
      from(session in AuthSession,
        where:
          session.active == true and is_nil(session.revoked_at) and session.expires_at > ^now,
        order_by: [desc: session.inserted_at]
      )
      |> Repo.all()

    {:ok, Enum.map(sessions, &%{jti: &1.jti, user_id: &1.user_id})}
  rescue
    _error -> {:error, :unavailable}
  end

  @doc "Revokes an online session by its public token identifier."
  @spec revoke_token(String.t()) :: :ok | {:error, :not_found | :unavailable}
  def revoke_token(jti) when is_binary(jti) and jti != "" do
    now = DateTime.utc_now()

    {count, _sessions} =
      Repo.delete_all(
        from(session in AuthSession,
          where:
            session.jti == ^jti and session.active == true and is_nil(session.revoked_at) and
              session.expires_at > ^now
        )
      )

    if count == 1, do: :ok, else: {:error, :not_found}
  rescue
    _error -> {:error, :unavailable}
  end

  def revoke_token(_jti), do: {:error, :not_found}

  defp lock_user(user_id) do
    Repo.query!("SELECT pg_advisory_xact_lock($1)", [user_id])
  end

  defp expire_user_sessions(user_id, now) do
    Repo.delete_all(
      from(session in AuthSession,
        where:
          session.user_id == ^user_id and session.active == true and is_nil(session.revoked_at) and
            session.expires_at <= ^now
      )
    )
  end

  defp active_session(user_id, now) do
    Repo.one(
      from(session in AuthSession,
        where:
          session.user_id == ^user_id and session.active == true and is_nil(session.revoked_at) and
            session.expires_at > ^now,
        order_by: [desc: session.inserted_at],
        limit: 1
      )
    )
  end

  defp revoke_user_sessions(user_id) do
    Repo.delete_all(
      from(session in AuthSession,
        where:
          session.user_id == ^user_id and session.active == true and is_nil(session.revoked_at)
      )
    )
  end

  defp activate_session(user_id, jti, expires_at) do
    case Repo.get_by(AuthSession, jti: jti) do
      nil ->
        case Repo.insert(
               AuthSession.changeset(%AuthSession{}, %{
                 user_id: user_id,
                 jti: jti,
                 expires_at: expires_at
               })
             ) do
          {:ok, _session} -> :ok
          {:error, _changeset} -> Repo.rollback(:unavailable)
        end

      %{user_id: ^user_id} = session ->
        case Repo.update(
               Ecto.Changeset.change(session,
                 active: true,
                 revoked_at: nil,
                 expires_at: expires_at
               )
             ) do
          {:ok, _session} -> :ok
          {:error, _changeset} -> Repo.rollback(:unavailable)
        end

      _session ->
        Repo.rollback(:invalid_session)
    end
  end

  defp occupy_result({:ok, :ok}), do: :ok

  defp occupy_result({:error, reason}) when reason in [:already_logged_in, :invalid_session],
    do: {:error, reason}

  defp occupy_result({:error, _reason}), do: {:error, :unavailable}
end
