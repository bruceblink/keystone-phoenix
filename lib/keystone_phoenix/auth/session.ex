defmodule KeystonePhoenix.Auth.Session do
  @moduledoc "PostgreSQL-backed refresh token sessions."

  import Ecto.Query

  alias KeystonePhoenix.Auth.AuthSession
  alias KeystonePhoenix.Repo
  alias KeystonePhoenix.User

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

  @doc "Validates and replaces a refresh session while holding the user lock."
  @spec rotate(integer(), String.t(), (map() -> {:ok, map()} | {:error, atom()})) ::
          {:ok, map()} | {:error, atom()}
  def rotate(user_id, jti, issue_tokens) when is_function(issue_tokens, 1) do
    now = DateTime.utc_now()

    Repo.transaction(fn ->
      lock_user(user_id)

      with true <- valid_in_transaction?(jti, user_id, now),
           {:ok, user} <- User.get_user(user_id),
           true <- user.status == 1,
           :ok <- revoke_in_transaction(user_id, jti),
           {:ok, tokens} <- issue_tokens.(user) do
        Map.put(tokens, :current_user, KeystonePhoenix.Auth.current_login_user(user))
      else
        {:error, reason} -> Repo.rollback(reason)
        _ -> Repo.rollback(:invalid_refresh_token)
      end
    end)
    |> rotate_result()
  rescue
    _error -> {:error, :unavailable}
  end

  @doc "Runs a login check while holding the user's session lock."
  @spec with_user_lock(integer(), (-> {:ok, term()} | {:error, term()})) ::
          {:ok, term()} | {:error, term()}
  def with_user_lock(user_id, authenticate) when is_function(authenticate, 0) do
    Repo.transaction(fn ->
      lock_user(user_id)

      case authenticate.() do
        {:ok, value} -> value
        {:error, reason} -> Repo.rollback({:locked_operation_failed, reason})
        _ -> Repo.rollback(:unavailable)
      end
    end)
    |> locked_operation_result()
  rescue
    _error -> {:error, :unavailable}
  end

  @doc """
  Runs an account update and session revocation in one transaction.

  The user lock serializes this operation with refresh rotation. A failed
  account update rolls back without revoking the current session.
  """
  @spec update_account_and_revoke(integer(), (-> {:ok, term()} | {:error, term()})) ::
          {:ok, term()} | {:error, term()}
  def update_account_and_revoke(user_id, update_account) when is_function(update_account, 0) do
    Repo.transaction(fn ->
      lock_user(user_id)

      case update_account.() do
        {:ok, value} ->
          revoke_user_sessions(user_id)
          {:ok, value}

        {:error, reason} ->
          Repo.rollback({:account_update_failed, reason})
      end
    end)
    |> account_update_result()
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
    Repo.transaction(fn ->
      lock_user(user_id)
      revoke_user_sessions(user_id)
    end)

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

  @doc "Counts active refresh sessions without loading session rows into memory."
  @spec count_active() :: {:ok, non_neg_integer()} | {:error, :unavailable}
  def count_active do
    now = DateTime.utc_now()

    count =
      Repo.aggregate(
        from(session in AuthSession,
          where:
            session.active == true and is_nil(session.revoked_at) and session.expires_at > ^now
        ),
        :count,
        :id
      )

    {:ok, count}
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

  defp valid_in_transaction?(jti, user_id, now) do
    Repo.exists?(
      from(session in AuthSession,
        where:
          session.jti == ^jti and session.user_id == ^user_id and session.active == true and
            is_nil(session.revoked_at) and session.expires_at > ^now
      )
    )
  end

  defp revoke_in_transaction(user_id, jti) do
    {count, _sessions} =
      Repo.delete_all(
        from(session in AuthSession,
          where:
            session.user_id == ^user_id and session.jti == ^jti and session.active == true and
              is_nil(session.revoked_at)
        )
      )

    if count == 1, do: :ok, else: Repo.rollback(:invalid_refresh_token)
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
        where: session.user_id == ^user_id
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

  defp rotate_result({:ok, tokens}), do: {:ok, tokens}

  defp rotate_result({:error, reason})
       when reason in [
              :invalid_refresh_token,
              :already_logged_in,
              :not_found,
              :token_configuration
            ] do
    case reason do
      :not_found -> {:error, :invalid_refresh_token}
      _ -> {:error, reason}
    end
  end

  defp rotate_result({:error, _reason}), do: {:error, :unavailable}

  defp account_update_result({:ok, {:ok, value}}), do: {:ok, value}

  defp account_update_result({:error, {:account_update_failed, reason}}),
    do: {:error, reason}

  defp account_update_result({:error, _reason}), do: {:error, :unavailable}

  defp locked_operation_result({:ok, value}), do: {:ok, value}

  defp locked_operation_result({:error, {:locked_operation_failed, reason}}),
    do: {:error, reason}

  defp locked_operation_result({:error, _reason}), do: {:error, :unavailable}
end
