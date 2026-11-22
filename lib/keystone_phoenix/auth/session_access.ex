defmodule KeystonePhoenix.Auth.SessionAccess do
  @moduledoc "当前 access token 标识的会话核验和 step-up 替换。"

  import Ecto.Query

  alias KeystonePhoenix.Auth.AuthSession
  alias KeystonePhoenix.Repo

  @recent_mfa_window_seconds 600
  @allowed_mfa_methods ["otp", "recovery"]

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
    replace_access_token(
      user_id,
      session_id,
      current_access_token_id,
      replacement_access_token_id,
      nil,
      nil
    )
  end

  def replace_access_token(
        _user_id,
        _session_id,
        _current_access_token_id,
        _replacement_access_token_id
      ),
      do: {:error, :invalid_token}

  @doc "在同一会话行事务中替换 access token，并可记录本次 MFA 验证。"
  def replace_access_token(
        user_id,
        session_id,
        current_access_token_id,
        replacement_access_token_id,
        verification,
        client_id
      )
      when is_binary(user_id) and is_binary(session_id) and is_binary(current_access_token_id) and
             is_binary(replacement_access_token_id) do
    with {:ok, mfa_fields} <- verification_fields(verification) do
      replace_access_token_locked(
        user_id,
        session_id,
        current_access_token_id,
        replacement_access_token_id,
        mfa_fields,
        client_id
      )
    end
  rescue
    _error -> {:error, :unavailable}
  end

  def replace_access_token(
        _user_id,
        _session_id,
        _current_access_token_id,
        _replacement_access_token_id,
        _verification,
        _client_id
      ),
      do: {:error, :invalid_token}

  @doc "在现有登录事务中记录刚创建会话的 MFA 验证结果。"
  def mark_mfa_verified(user_id, session_id, client_id, verification)
      when is_binary(user_id) and is_binary(session_id) and is_binary(client_id) do
    with {:ok, mfa_fields} <- verification_fields(verification) do
      session =
        Repo.one(
          from current in AuthSession,
            where:
              current.id == ^session_id and current.user_id == ^user_id and
                current.client_id == ^client_id and current.active == true and
                is_nil(current.revoked_at),
            lock: "FOR UPDATE"
        )

      case session do
        %AuthSession{} = current ->
          case current |> Ecto.Changeset.change(mfa_fields) |> Repo.update() do
            {:ok, _updated} -> :ok
            {:error, _changeset} -> {:error, :unavailable}
          end

        nil ->
          {:error, :unavailable}
      end
    end
  rescue
    _error -> {:error, :unavailable}
  end

  def mark_mfa_verified(_user_id, _session_id, _client_id, _verification),
    do: {:error, :unavailable}

  @doc "检查令牌指向的有效会话是否在最近 600 秒完成 OTP 或恢复码验证。"
  def recent_mfa_authentication?(user_id, session_id, client_id, access_token_id)
      when is_binary(user_id) and is_binary(session_id) and is_binary(client_id) and
             is_binary(access_token_id) do
    result =
      DateTime.utc_now()
      |> then(fn now ->
        cutoff = DateTime.add(now, -@recent_mfa_window_seconds, :second)

        allowed_methods = @allowed_mfa_methods

        query =
          from current in AuthSession,
            where:
              current.id == ^session_id and current.user_id == ^user_id and
                current.access_token_id == ^access_token_id and current.active == true and
                is_nil(current.revoked_at) and current.refresh_expires_at > ^now and
                current.idle_expires_at > ^now and current.mfa_verified_at >= ^cutoff and
                current.mfa_assurance == "AAL2" and current.mfa_amr in ^allowed_methods

        query = where(query, [current], current.client_id == ^client_id)
        Repo.exists?(query)
      end)

    {:ok, result}
  rescue
    _error -> {:error, :unavailable}
  end

  defp replace_access_token_locked(
         user_id,
         session_id,
         current_access_token_id,
         replacement_access_token_id,
         mfa_fields,
         client_id
       ) do
    result =
      Repo.transaction(fn ->
        lock_user(user_id)
        now = DateTime.utc_now()

        query =
          from current in AuthSession,
            where:
              current.id == ^session_id and current.user_id == ^user_id and
                current.access_token_id == ^current_access_token_id and current.active == true and
                is_nil(current.revoked_at) and current.refresh_expires_at > ^now and
                current.idle_expires_at > ^now,
            lock: "FOR UPDATE"

        query =
          if is_binary(client_id),
            do: where(query, [current], current.client_id == ^client_id),
            else: query

        session = Repo.one(query)

        case session do
          %AuthSession{} = current ->
            attrs =
              Map.merge(mfa_fields, %{
                access_token_id: replacement_access_token_id,
                last_seen_at: DateTime.utc_now()
              })

            case current |> Ecto.Changeset.change(attrs) |> Repo.update() do
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
  end

  defp verification_fields(nil), do: {:ok, %{}}

  defp verification_fields(%{
         assurance: "AAL2",
         amr: amr,
         verified_at: %DateTime{} = verified_at
       })
       when amr in @allowed_mfa_methods do
    {:ok,
     %{
       mfa_verified_at: verified_at,
       mfa_assurance: "AAL2",
       mfa_amr: amr
     }}
  end

  defp verification_fields(_verification), do: {:error, :invalid_mfa_verification}

  defp lock_user(user_id),
    do: Repo.query!("SELECT pg_advisory_xact_lock(hashtextextended($1, 0))", [user_id])
end
