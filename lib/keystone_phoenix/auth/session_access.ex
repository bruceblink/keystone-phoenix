defmodule KeystonePhoenix.Auth.SessionAccess do
  @moduledoc "当前 access token 标识的会话核验和 step-up 替换。"

  import Ecto.Query

  alias KeystonePhoenix.Auth.AuthSession
  alias KeystonePhoenix.Repo

  @doc "只核验当前会话绑定的 access token id。"
  def active_access?(user_id, access_token_id)
      when is_binary(user_id) and is_binary(access_token_id) do
    now = DateTime.utc_now()

    Repo.exists?(
      from session in AuthSession,
        where:
          session.user_id == ^user_id and session.access_token_id == ^access_token_id and
            session.active == true and is_nil(session.revoked_at) and
            session.refresh_expires_at > ^now and session.idle_expires_at > ^now
    )
  rescue
    _error -> false
  end

  def active_access?(_user_id, _access_token_id), do: false

  @doc "在会话行锁内替换 access token id，保留 refresh token 族和到期状态。"
  def replace_access_token(
        user_id,
        session_id,
        current_access_token_id,
        replacement_access_token_id
      )
      when is_binary(user_id) and is_binary(session_id) and is_binary(current_access_token_id) and
             is_binary(replacement_access_token_id) do
    result =
      Repo.transaction(fn ->
        lock_user(user_id)

        session =
          Repo.one(
            from current in AuthSession,
              where:
                current.id == ^session_id and current.user_id == ^user_id and
                  current.access_token_id == ^current_access_token_id and
                  current.active == true and is_nil(current.revoked_at),
              lock: "FOR UPDATE"
          )

        case session do
          %AuthSession{} = current ->
            case current
                 |> Ecto.Changeset.change(
                   access_token_id: replacement_access_token_id,
                   last_seen_at: DateTime.utc_now()
                 )
                 |> Repo.update() do
              {:ok, _updated} -> :ok
              {:error, _changeset} -> Repo.rollback(:unavailable)
            end

          nil ->
            Repo.rollback(:invalid_token)
        end
      end)

    case result do
      {:ok, :ok} -> :ok
      {:error, :invalid_token} -> {:error, :invalid_token}
      _ -> {:error, :unavailable}
    end
  rescue
    _error -> {:error, :unavailable}
  end

  def replace_access_token(
        _user_id,
        _session_id,
        _current_access_token_id,
        _replacement_access_token_id
      ),
      do: {:error, :invalid_token}

  defp lock_user(user_id),
    do: Repo.query!("SELECT pg_advisory_xact_lock(hashtextextended($1, 0))", [user_id])
end
