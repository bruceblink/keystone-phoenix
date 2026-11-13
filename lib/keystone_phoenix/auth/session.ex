defmodule KeystonePhoenix.Auth.Session do
  @moduledoc "PostgreSQL-backed session, refresh family and rotation state."

  import Ecto.Query

  alias KeystonePhoenix.Auth.{AuthSession, RefreshToken, RefreshTokenEvent}
  alias KeystonePhoenix.Identity
  alias KeystonePhoenix.Repo
  alias KeystonePhoenix.User

  @default_client_id "web"
  @idle_lifetime 86_400

  @doc "生成新的会话 ID；调用方必须在签发令牌前把它写入 sid。"
  def new_session_id, do: Identity.v7()

  @doc "在用户锁内创建一个刷新会话和刷新令牌记录。"
  def occupy(
        user_id,
        jti,
        ttl,
        force_login \\ false,
        session_id \\ nil,
        client_id \\ @default_client_id,
        refresh_token \\ nil
      ) do
    now = DateTime.utc_now()
    session_id = session_id || new_session_id()
    expires_at = DateTime.add(now, ttl, :second)
    client_id = normalize_client_id(client_id)

    Repo.transaction(fn ->
      lock_user(user_id)
      expire_user_sessions(user_id, now)

      case active_session(user_id, now) do
        nil ->
          activate_session(user_id, jti, session_id, client_id, expires_at, now, refresh_token)

        %{jti: ^jti, id: ^session_id} ->
          :ok

        _session when force_login ->
          revoke_user_sessions(user_id, now)
          activate_session(user_id, jti, session_id, client_id, expires_at, now, refresh_token)

        _session ->
          Repo.rollback(:already_logged_in)
      end
    end)
    |> occupy_result()
  rescue
    _error -> {:error, :unavailable}
  end

  @doc "在用户锁和会话行锁内轮换刷新令牌；重用旧令牌会撤销整个令牌族。"
  def rotate(user_id, jti, session_id, refresh_token, issue_tokens)
      when is_function(issue_tokens, 2) do
    now = DateTime.utc_now()

    Repo.transaction(fn ->
      lock_user(user_id)

      with %AuthSession{} = session <- current_session(user_id, jti, session_id),
           {:ok, user} <- User.get_user(user_id),
           true <- user.status == 1,
           :ok <- verify_current_refresh(session, jti, refresh_token, now),
           {:ok, tokens} <- issue_tokens.(user, session),
           :ok <- persist_rotation(session, jti, tokens, now) do
        Map.put(tokens, :current_user, KeystonePhoenix.Auth.current_login_user(user))
      else
        {:reuse, reason} -> {:error, reason}
        {:error, reason} -> Repo.rollback(reason)
        _ -> Repo.rollback(:invalid_refresh_token)
      end
    end)
    |> rotate_result()
  rescue
    _error -> {:error, :unavailable}
  end

  def rotate(user_id, jti, session_id, issue_tokens) when is_function(issue_tokens, 2) do
    rotate(user_id, jti, session_id, nil, issue_tokens)
  end

  @doc "保留旧调用形式，供低层测试和内部工具使用。"
  def rotate(user_id, jti, issue_tokens) when is_function(issue_tokens, 1) do
    case Repo.one(
           from session in AuthSession,
             where: session.user_id == ^user_id and session.jti == ^jti,
             select: session.id
         ) do
      session_id when is_binary(session_id) ->
        rotate(user_id, jti, session_id, nil, fn user, _session -> issue_tokens.(user) end)

      _ ->
        {:error, :invalid_refresh_token}
    end
  end

  @doc "在用户锁内执行登录或账号操作。"
  def with_user_lock(user_id, operation) when is_function(operation, 0) do
    Repo.transaction(fn ->
      lock_user(user_id)

      case operation.() do
        {:ok, value} -> value
        {:error, reason} -> Repo.rollback({:locked_operation_failed, reason})
        _ -> Repo.rollback(:unavailable)
      end
    end)
    |> locked_operation_result()
  rescue
    _error -> {:error, :unavailable}
  end

  @doc "在同一事务中完成账号更新和会话撤销。"
  def update_account_and_revoke(user_id, update_account) when is_function(update_account, 0) do
    Repo.transaction(fn ->
      lock_user(user_id)

      case update_account.() do
        {:ok, value} ->
          revoke_user_sessions(user_id, DateTime.utc_now())
          {:ok, value}

        {:error, reason} ->
          Repo.rollback({:account_update_failed, reason})
      end
    end)
    |> account_update_result()
  rescue
    _error -> {:error, :unavailable}
  end

  @doc "按会话 ID 或当前刷新令牌 ID检查活动状态。"
  def valid?(target, user_id) do
    now = DateTime.utc_now()

    Repo.exists?(
      from session in AuthSession,
        where:
          session.user_id == ^user_id and (session.id == ^target or session.jti == ^target) and
            session.active == true and is_nil(session.revoked_at) and
            session.refresh_expires_at > ^now and session.idle_expires_at > ^now
    )
  rescue
    _error -> false
  end

  def active?(user_id, target), do: valid?(target, user_id)

  @doc "撤销指定用户的当前会话。"
  def release(user_id, target), do: revoke_target(user_id, target)
  def revoke(user_id, target), do: release(user_id, target)

  @doc "撤销指定会话 ID及其刷新令牌。"
  def revoke_session(session_id) when is_binary(session_id) do
    now = DateTime.utc_now()

    case Repo.get(AuthSession, session_id) do
      %AuthSession{user_id: user_id} -> revoke_target(user_id, session_id, now)
      nil -> :ok
    end
  rescue
    _error -> :ok
  end

  def revoke_session(_session_id), do: :ok

  def revoke_account(user_id) do
    Repo.transaction(fn ->
      lock_user(user_id)
      revoke_user_sessions(user_id, DateTime.utc_now())
    end)

    :ok
  rescue
    _error -> :ok
  end

  def delete(jti), do: revoke_target(nil, jti)

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

  def revoke_token(target) when is_binary(target) and target != "" do
    case find_session(target) do
      %AuthSession{user_id: user_id} -> revoke_target(user_id, target)
      nil -> {:error, :not_found}
    end
  rescue
    _error -> {:error, :unavailable}
  end

  def revoke_token(_target), do: {:error, :not_found}

  defp current_session(user_id, _jti, session_id) do
    query =
      from(session in AuthSession,
        where: session.user_id == ^user_id and session.id == ^session_id,
        lock: "FOR UPDATE"
      )

    Repo.one(query)
  end

  defp verify_current_refresh(session, jti, refresh_token, now) do
    token = Repo.get(RefreshToken, jti)

    cond do
      is_nil(token) ->
        {:error, :invalid_refresh_token}

      token.session_id != session.id ->
        {:error, :invalid_refresh_token}

      token.token_hash != hash(refresh_token || jti) ->
        {:error, :invalid_refresh_token}

      not is_nil(token.revoked_at) or not is_nil(token.reused_at) ->
        reuse_result(session, jti, now)

      token.expires_at <= now or token.idle_expires_at <= now ->
        reuse_result(session, jti, now)

      session.refresh_expires_at <= now or session.idle_expires_at <= now ->
        reuse_result(session, jti, now)

      true ->
        :ok
    end
  end

  defp persist_rotation(session, old_jti, tokens, now) do
    new_jti = Map.get(tokens, :refresh_jti)
    refresh_expires_at = DateTime.add(now, Map.fetch!(tokens, :refresh_expires_in), :second)

    idle_expires_at =
      min_datetime(DateTime.add(now, @idle_lifetime, :second), session.refresh_expires_at)

    if not Identity.canonical?(new_jti) or new_jti == old_jti do
      Repo.rollback(:invalid_refresh_token)
    end

    Repo.update_all(from(token in RefreshToken, where: token.id == ^old_jti),
      set: [revoked_at: now]
    )

    {:ok, _token} =
      %RefreshToken{}
      |> RefreshToken.changeset(%{
        id: new_jti,
        session_id: session.id,
        user_id: session.user_id,
        refresh_family_id: session.refresh_family_id,
        token_hash: hash(Map.get(tokens, :refresh_token) || new_jti),
        expires_at: refresh_expires_at,
        idle_expires_at: idle_expires_at
      })
      |> Repo.insert()

    {:ok, _updated} =
      session
      |> Ecto.Changeset.change(
        jti: new_jti,
        refresh_expires_at: refresh_expires_at,
        idle_expires_at: idle_expires_at,
        last_seen_at: now,
        expires_at: refresh_expires_at
      )
      |> Repo.update()

    record_event(
      new_jti,
      session.user_id,
      session.refresh_family_id,
      "ROTATED",
      session.client_id,
      nil
    )

    :ok
  rescue
    Ecto.NoResultsError -> Repo.rollback(:unavailable)
  end

  defp activate_session(user_id, jti, session_id, client_id, expires_at, now, refresh_token) do
    family_id = Identity.v7()
    idle_expires_at = min_datetime(DateTime.add(now, @idle_lifetime, :second), expires_at)

    attrs = %{
      id: session_id,
      user_id: user_id,
      client_id: client_id,
      jti: jti,
      refresh_family_id: family_id,
      refresh_expires_at: expires_at,
      idle_expires_at: idle_expires_at,
      last_seen_at: now,
      expires_at: expires_at,
      active: true,
      revoked_at: nil
    }

    with {:ok, session} <- Repo.insert(AuthSession.changeset(%AuthSession{}, attrs)),
         {:ok, _token} <-
           insert_refresh_token(session, jti, expires_at, idle_expires_at, refresh_token),
         :ok <- record_event(jti, user_id, family_id, "ISSUED", client_id, nil) do
      :ok
    else
      {:error, _changeset} -> Repo.rollback(:unavailable)
      _ -> Repo.rollback(:unavailable)
    end
  end

  defp insert_refresh_token(session, jti, expires_at, idle_expires_at, refresh_token) do
    %RefreshToken{}
    |> RefreshToken.changeset(%{
      id: jti,
      session_id: session.id,
      user_id: session.user_id,
      refresh_family_id: session.refresh_family_id,
      token_hash: hash(refresh_token || jti),
      expires_at: expires_at,
      idle_expires_at: idle_expires_at
    })
    |> Repo.insert()
  end

  defp revoke_target(user_id, target, now \\ DateTime.utc_now()) do
    query =
      case user_id do
        nil ->
          from(session in AuthSession,
            where: session.id == ^target or session.jti == ^target
          )

        user_id ->
          from(session in AuthSession,
            where:
              session.user_id == ^user_id and
                (session.id == ^target or session.jti == ^target)
          )
      end

    sessions = Repo.all(query)
    Repo.update_all(query, set: [active: false, revoked_at: now])

    Enum.each(sessions, fn session ->
      revoke_family(session.refresh_family_id, now)

      record_event(
        session.jti,
        session.user_id,
        session.refresh_family_id,
        "REVOKED",
        session.client_id,
        nil
      )
    end)

    :ok
  rescue
    _error -> :ok
  end

  defp revoke_user_sessions(user_id, now) do
    sessions = Repo.all(from(session in AuthSession, where: session.user_id == ^user_id))

    Repo.update_all(from(session in AuthSession, where: session.user_id == ^user_id),
      set: [active: false, revoked_at: now]
    )

    Enum.each(sessions, &revoke_family(&1.refresh_family_id, now))
    :ok
  end

  defp revoke_family(family_id, now) do
    Repo.update_all(from(token in RefreshToken, where: token.refresh_family_id == ^family_id),
      set: [revoked_at: now]
    )

    Repo.update_all(from(session in AuthSession, where: session.refresh_family_id == ^family_id),
      set: [active: false, revoked_at: now]
    )

    :ok
  end

  # 重用旧令牌时标记整个刷新族，保留 revoked_at 的首次时间。
  defp mark_family_reused(session, now) do
    Repo.update_all(
      from(token in RefreshToken,
        where: token.refresh_family_id == ^session.refresh_family_id and is_nil(token.reused_at)
      ),
      set: [reused_at: now]
    )

    revoke_family(session.refresh_family_id, now)
  end

  defp reuse_result(session, jti, now) do
    mark_family_reused(session, now)

    record_event(
      jti,
      session.user_id,
      session.refresh_family_id,
      "REUSE_DETECTED",
      session.client_id,
      nil
    )

    {:reuse, :invalid_refresh_token}
  end

  defp expire_user_sessions(user_id, now) do
    expired =
      Repo.all(
        from(session in AuthSession,
          where:
            session.user_id == ^user_id and session.active == true and
              (session.refresh_expires_at <= ^now or session.idle_expires_at <= ^now)
        )
      )

    Repo.update_all(
      from(session in AuthSession,
        where:
          session.user_id == ^user_id and session.active == true and
            (session.refresh_expires_at <= ^now or session.idle_expires_at <= ^now)
      ),
      set: [active: false, revoked_at: now]
    )

    Enum.each(expired, &revoke_family(&1.refresh_family_id, now))
    :ok
  end

  defp active_session(user_id, now) do
    Repo.one(
      from(session in AuthSession,
        where:
          session.user_id == ^user_id and session.active == true and is_nil(session.revoked_at) and
            session.refresh_expires_at > ^now and session.idle_expires_at > ^now,
        order_by: [desc: session.inserted_at],
        limit: 1
      )
    )
  end

  defp find_session(target) do
    Repo.one(
      from(session in AuthSession,
        where:
          (session.id == ^target or session.jti == ^target) and session.active == true and
            is_nil(session.revoked_at),
        limit: 1
      )
    )
  end

  defp lock_user(user_id),
    do: Repo.query!("SELECT pg_advisory_xact_lock(hashtextextended($1, 0))", [user_id])

  defp record_event(token_id, user_id, family_id, event_type, client_id, detail) do
    Repo.insert!(%RefreshTokenEvent{
      id: Identity.v7(),
      token_id: token_id,
      user_id: user_id,
      refresh_family_id: family_id,
      event_type: event_type,
      client_id: client_id,
      detail: detail
    })

    :ok
  end

  defp min_datetime(left, right),
    do: if(DateTime.compare(left, right) == :lt, do: left, else: right)

  defp hash(value), do: :crypto.hash(:sha256, value) |> Base.encode16(case: :lower)
  defp normalize_client_id(value) when is_binary(value) and value != "", do: value
  defp normalize_client_id(_value), do: @default_client_id

  defp occupy_result({:ok, :ok}), do: :ok

  defp occupy_result({:error, reason}) when reason in [:already_logged_in, :invalid_session],
    do: {:error, reason}

  defp occupy_result({:error, _reason}), do: {:error, :unavailable}

  defp rotate_result({:ok, tokens}) when is_map(tokens), do: {:ok, tokens}

  defp rotate_result({:ok, {:error, reason}}), do: {:error, reason}

  defp rotate_result({:error, reason})
       when reason in [:invalid_refresh_token, :already_logged_in, :token_configuration],
       do: {:error, reason}

  defp rotate_result({:error, _reason}), do: {:error, :unavailable}

  defp account_update_result({:ok, {:ok, value}}), do: {:ok, value}
  defp account_update_result({:error, {:account_update_failed, reason}}), do: {:error, reason}
  defp account_update_result({:error, _reason}), do: {:error, :unavailable}

  defp locked_operation_result({:ok, value}), do: {:ok, value}
  defp locked_operation_result({:error, {:locked_operation_failed, reason}}), do: {:error, reason}
  defp locked_operation_result({:error, _reason}), do: {:error, :unavailable}
end
