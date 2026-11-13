defmodule KeystonePhoenix.Auth.Mfa do
  @moduledoc """
  Phoenix MFA 领域服务。

  该服务与认证入口和会话签发解耦。它只负责 TOTP enrollment、登录挑战、step-up、
  恢复码轮换和一次性消费；Controller 或 Plug 负责把成功结果写入规范 Principal。
  所有状态改变都在 Repo 事务内完成，并以认证请求、因子和恢复码的行锁保证并发时
  只有一个请求成功。
  """

  import Ecto.Query

  alias KeystonePhoenix.Auth.Mfa.{
    Challenge,
    Factor,
    RecoveryCode,
    RecoveryRecord,
    RateLimiter,
    SecretCipher,
    Totp
  }

  alias KeystonePhoenix.Repo
  alias KeystonePhoenix.User.SysUser

  @default_client_id "web"
  @max_attempts 5
  @challenge_lifetime_seconds 300
  @factor_lock_seconds 300

  @type verification :: %{assurance: String.t(), amr: String.t()}

  @doc "读取用户 MFA 策略和当前 TOTP 因子状态，不返回密钥或恢复码。"
  def status(user_id) do
    with {:ok, user_id} <- canonical_id(user_id),
         %SysUser{} = user <- Repo.get_by(SysUser, user_id: user_id, deleted: false) do
      factor = Repo.get_by(Factor, user_id: user_id)

      {:ok,
       %{
         user_id: user_id,
         required: user.mfa_required,
         enabled: match?(%Factor{enabled: true}, factor),
         factor_id: if(factor, do: factor.id)
       }}
    else
      nil -> {:error, :user_not_found}
      {:error, _} = error -> error
    end
  end

  @doc "密码成功后准备登录 MFA 挑战；未启用 MFA 时不创建挑战。"
  def prepare_login(user_id, client_id \\ @default_client_id) do
    with {:ok, status} <- status(user_id),
         true <- status.required do
      if status.enabled do
        with {:ok, client_id} <- normalize_client_id(client_id),
             {:ok, challenge} <- create_challenge(status.user_id, "LOGIN", client_id, nil, nil) do
          {:ok, %{required: true, challenge: challenge}}
        end
      else
        {:ok, %{required: true, challenge: nil}}
      end
    else
      false -> {:ok, %{required: false, challenge: nil}}
      {:error, _} = error -> error
    end
  end

  @doc "为当前人类会话创建待验证 enrollment，并只返回一次密钥材料。"
  def begin_enrollment(user_id, username, client_id \\ @default_client_id, session_id) do
    with {:ok, user_id} <- canonical_id(user_id),
         {:ok, client_id} <- normalize_client_id(client_id),
         {:ok, session_id} <- required_id(session_id) do
      run_transaction(fn ->
        _user = lock_user!(user_id)
        factor = Repo.get_by(Factor, user_id: user_id)

        if match?(%Factor{enabled: true}, factor), do: Repo.rollback(:mfa_already_enabled)

        # 在写入待验证密文前检查恢复码配置，避免 enrollment 成功后无法生成恢复码。
        _ = RecoveryCode.generate_batch()
        factor_id = KeystonePhoenix.Identity.v7()
        secret = Totp.generate_secret()
        encrypted = SecretCipher.encrypt(user_id, factor_id, secret)

        if factor, do: Repo.delete!(factor)

        %Factor{}
        |> Factor.changeset(%{
          id: factor_id,
          user_id: user_id,
          mfa_type: "TOTP",
          secret_ciphertext: encrypted.ciphertext,
          secret_nonce: encrypted.nonce,
          key_version: encrypted.key_version,
          enabled: false
        })
        |> Repo.insert!()

        challenge = create_challenge!(user_id, "ENROLL", client_id, session_id, nil)

        %{
          challenge_id: challenge.id,
          factor_id: factor_id,
          secret: secret,
          otpauth_uri: Totp.otpauth_uri(username, secret),
          expires_at: challenge.expires_at
        }
      end)
    end
  end

  @doc "校验 enrollment TOTP，启用因子并原子替换恢复码批次。"
  def verify_enrollment(user_id, challenge_id, client_id, session_id, code, ip_address \\ nil) do
    with {:ok, user_id} <- canonical_id(user_id),
         {:ok, challenge_id} <- canonical_id(challenge_id),
         {:ok, client_id} <- normalize_client_id(client_id),
         {:ok, session_id} <- required_id(session_id),
         false <- RateLimiter.blocked?(user_id, ip_address) do
      result =
        run_transaction(fn ->
          now = DateTime.utc_now()

          challenge =
            lock_active_challenge!(challenge_id, user_id, client_id, "ENROLL", session_id, now)

          factor = lock_factor!(user_id)

          if factor == nil or factor.enabled, do: Repo.rollback(:invalid_challenge)
          verify_enrollment_code(user_id, challenge, factor, code, now)
        end)

      after_verification(result, user_id, ip_address)
    else
      true -> {:error, :rate_limited}
      {:error, _} = error -> error
    end
  end

  @doc "校验登录或 step-up 的 TOTP/恢复码，并返回 AAL2 认证结果。"
  def verify_login(user_id, challenge_id, client_id, code, ip_address \\ nil),
    do: verify_factor(user_id, challenge_id, client_id, nil, "LOGIN", code, ip_address)

  def verify_step_up(user_id, challenge_id, client_id, session_id, code, ip_address \\ nil),
    do: verify_factor(user_id, challenge_id, client_id, session_id, "STEP_UP", code, ip_address)

  @doc "为敏感写操作创建绑定当前会话的短期 step-up 请求。"
  def begin_step_up(user_id, client_id, session_id, context_hash \\ nil) do
    with {:ok, status} <- status(user_id),
         true <- status.enabled,
         {:ok, client_id} <- normalize_client_id(client_id),
         {:ok, session_id} <- required_id(session_id),
         {:ok, context_hash} <- normalize_context_hash(context_hash) do
      create_challenge(status.user_id, "STEP_UP", client_id, session_id, context_hash)
    else
      false -> {:error, :mfa_not_enrolled}
      {:error, _} = error -> error
    end
  end

  @doc "只有已完成 enrollment 的用户才可以启用强制 MFA 策略。"
  def set_required(user_id, required) when is_boolean(required) do
    with {:ok, user_id} <- canonical_id(user_id) do
      run_transaction(fn ->
        user = lock_user!(user_id)
        factor = Repo.get_by(Factor, user_id: user_id)

        if required and not match?(%Factor{enabled: true}, factor),
          do: Repo.rollback(:mfa_not_enrolled)

        if user.mfa_required != required do
          user
          |> Ecto.Changeset.change(
            mfa_required: required,
            permission_version: user.permission_version + 1
          )
          |> Repo.update!()
        end

        :ok
      end)
    end
  end

  def set_required(_user_id, _required), do: {:error, :validation_failed}

  @doc "生成新恢复码批次并原子替换旧批次；明文只返回本次调用结果。"
  def rotate_recovery_codes(user_id) do
    with {:ok, user_id} <- canonical_id(user_id) do
      run_transaction(fn ->
        _user = lock_user!(user_id)
        factor = lock_factor!(user_id)
        if factor == nil or not factor.enabled, do: Repo.rollback(:mfa_not_enrolled)
        batch = RecoveryCode.generate_batch()
        replace_recovery_codes!(user_id, batch)
        batch.codes
      end)
    end
  end

  defp verify_factor(user_id, challenge_id, client_id, session_id, purpose, code, ip_address) do
    with {:ok, user_id} <- canonical_id(user_id),
         {:ok, challenge_id} <- canonical_id(challenge_id),
         {:ok, client_id} <- normalize_client_id(client_id),
         {:ok, session_id} <- optional_id(session_id),
         false <- RateLimiter.blocked?(user_id, ip_address) do
      result =
        run_transaction(fn ->
          now = DateTime.utc_now()

          challenge =
            lock_active_challenge!(challenge_id, user_id, client_id, purpose, session_id, now)

          factor = lock_factor!(user_id)

          if factor == nil or not factor.enabled, do: Repo.rollback(:mfa_not_enrolled)
          verify_factor_code(user_id, challenge, factor, code, now)
        end)

      after_verification(result, user_id, ip_address)
    else
      true -> {:error, :rate_limited}
      {:error, _} = error -> error
    end
  end

  defp verify_enrollment_code(user_id, challenge, factor, code, now) do
    secret = decrypt_factor!(user_id, factor)

    case accepted_step(secret, factor, code, now) do
      {:ok, step} ->
        batch = RecoveryCode.generate_batch()

        factor
        |> Ecto.Changeset.change(
          enabled: true,
          enrolled_at: now,
          last_used_at: now,
          last_accepted_step: step,
          failed_attempt_count: 0,
          locked_until: nil
        )
        |> Repo.update!()

        consume_challenge!(challenge, now)
        replace_recovery_codes!(user_id, batch)
        bump_permission_version!(user_id)
        {:ok, %{assurance: "AAL2", amr: "otp", recovery_codes: batch.codes}}

      :error ->
        register_failure!(challenge, factor, now)
        {:error, :invalid_mfa_code}
    end
  end

  defp verify_factor_code(user_id, challenge, factor, code, now) do
    secret = decrypt_factor!(user_id, factor)

    case accepted_step(secret, factor, code, now) do
      {:ok, step} ->
        factor
        |> Ecto.Changeset.change(
          last_accepted_step: step,
          last_used_at: now,
          failed_attempt_count: 0,
          locked_until: nil
        )
        |> Repo.update!()

        consume_challenge!(challenge, now)
        {:ok, %{assurance: "AAL2", amr: "otp"}}

      :error ->
        case consume_recovery_code!(user_id, code, now) do
          true ->
            factor
            |> Ecto.Changeset.change(
              last_used_at: now,
              failed_attempt_count: 0,
              locked_until: nil
            )
            |> Repo.update!()

            consume_challenge!(challenge, now)
            {:ok, %{assurance: "AAL2", amr: "recovery"}}

          false ->
            register_failure!(challenge, factor, now)
            {:error, :invalid_mfa_code}
        end
    end
  end

  defp decrypt_factor!(user_id, factor) do
    SecretCipher.decrypt(user_id, factor.id, %{
      ciphertext: factor.secret_ciphertext,
      nonce: factor.secret_nonce,
      key_version: factor.key_version
    })
  end

  defp accepted_step(secret, factor, code, now) do
    with {:ok, step} <- Totp.matching_step(secret, code, DateTime.to_unix(now)),
         true <- is_nil(factor.last_accepted_step) or step > factor.last_accepted_step,
         true <- is_nil(factor.locked_until) or DateTime.compare(factor.locked_until, now) != :gt do
      {:ok, step}
    else
      _ -> :error
    end
  end

  defp consume_recovery_code!(user_id, code, now) do
    case RecoveryCode.normalize(code) do
      :error ->
        false

      normalized ->
        hash = RecoveryCode.hash(normalized)

        query =
          from record in RecoveryRecord,
            where:
              record.user_id == ^user_id and record.code_hash == ^hash and is_nil(record.used_at),
            lock: "FOR UPDATE"

        case Repo.one(query) do
          nil ->
            false

          record ->
            Repo.update!(Ecto.Changeset.change(record, used_at: now))
            true
        end
    end
  end

  defp register_failure!(challenge, factor, now) do
    challenge
    |> Ecto.Changeset.change(attempt_count: challenge.attempt_count + 1)
    |> Repo.update!()

    locked_until =
      if factor.failed_attempt_count + 1 >= @max_attempts,
        do: DateTime.add(now, @factor_lock_seconds, :second)

    factor
    |> Ecto.Changeset.change(
      failed_attempt_count: factor.failed_attempt_count + 1,
      locked_until: locked_until
    )
    |> Repo.update!()
  end

  defp lock_user!(user_id) do
    Repo.one!(
      from user in SysUser,
        where: user.user_id == ^user_id and user.deleted == false,
        lock: "FOR UPDATE"
    )
  rescue
    Ecto.NoResultsError -> Repo.rollback(:user_not_found)
  end

  defp lock_factor!(user_id),
    do: Repo.one(from factor in Factor, where: factor.user_id == ^user_id, lock: "FOR UPDATE")

  defp lock_active_challenge!(challenge_id, user_id, client_id, purpose, session_id, now) do
    query =
      from challenge in Challenge,
        where:
          challenge.id == ^challenge_id and challenge.user_id == ^user_id and
            challenge.client_id == ^client_id and challenge.purpose == ^purpose and
            is_nil(challenge.consumed_at) and challenge.expires_at > ^now and
            challenge.attempt_count < @max_attempts,
        lock: "FOR UPDATE"

    query =
      if is_nil(session_id),
        do: where(query, [challenge], is_nil(challenge.session_id)),
        else: where(query, [challenge], challenge.session_id == ^session_id)

    case Repo.one(query) do
      nil -> Repo.rollback(:invalid_challenge)
      challenge -> challenge
    end
  end

  defp consume_challenge!(challenge, now) do
    challenge
    |> Ecto.Changeset.change(consumed_at: now)
    |> Repo.update!()
  end

  defp replace_recovery_codes!(user_id, batch) do
    now = DateTime.utc_now()
    Repo.delete_all(from record in RecoveryRecord, where: record.user_id == ^user_id)

    rows =
      Enum.map(batch.codes, fn code ->
        %{
          id: KeystonePhoenix.Identity.v7(),
          user_id: user_id,
          batch_id: batch.batch_id,
          code_hash: RecoveryCode.hash(code),
          inserted_at: now,
          updated_at: now
        }
      end)

    {count, _} = Repo.insert_all(RecoveryRecord, rows)
    if count != RecoveryCode.count(), do: Repo.rollback(:recovery_codes_not_saved)
    :ok
  end

  defp bump_permission_version!(user_id) do
    Repo.update_all(from(user in SysUser, where: user.user_id == ^user_id),
      inc: [permission_version: 1]
    )
  end

  defp create_challenge(user_id, purpose, client_id, session_id, context_hash) do
    run_transaction(fn ->
      create_challenge!(user_id, purpose, client_id, session_id, context_hash)
    end)
  end

  defp create_challenge!(user_id, purpose, client_id, session_id, context_hash) do
    expires_at = DateTime.add(DateTime.utc_now(), challenge_lifetime(), :second)

    %Challenge{}
    |> Challenge.changeset(%{
      id: KeystonePhoenix.Identity.v7(),
      user_id: user_id,
      purpose: purpose,
      client_id: client_id,
      session_id: session_id,
      context_hash: context_hash,
      expires_at: expires_at,
      attempt_count: 0
    })
    |> Repo.insert!()
    |> Map.take([
      :id,
      :purpose,
      :client_id,
      :session_id,
      :context_hash,
      :expires_at,
      :attempt_count
    ])
  end

  defp challenge_lifetime do
    value =
      Application.get_env(
        :keystone_phoenix,
        :mfa_challenge_lifetime_seconds,
        @challenge_lifetime_seconds
      )

    if is_integer(value) and value in 60..600,
      do: value,
      else: raise(ArgumentError, "invalid MFA challenge lifetime")
  end

  defp normalize_client_id(value) do
    value =
      if is_binary(value) and value != "",
        do: String.trim(value) |> String.downcase(),
        else: @default_client_id

    if Regex.match?(~r/^[a-z0-9][a-z0-9._-]{0,63}$/, value),
      do: {:ok, value},
      else: {:error, :validation_failed}
  end

  defp normalize_context_hash(nil), do: {:ok, nil}

  defp normalize_context_hash(value) when is_binary(value) do
    if Regex.match?(~r/^[0-9a-f]{64}$/, value),
      do: {:ok, value},
      else: {:error, :validation_failed}
  end

  defp normalize_context_hash(_value), do: {:error, :validation_failed}

  defp canonical_id(value) do
    if KeystonePhoenix.Identity.canonical?(value),
      do: {:ok, value},
      else: {:error, :validation_failed}
  end

  defp required_id(value) do
    case canonical_id(value) do
      {:ok, id} -> {:ok, id}
      _ -> {:error, :validation_failed}
    end
  end

  defp optional_id(nil), do: {:ok, nil}
  defp optional_id(value), do: required_id(value)

  defp run_transaction(function) do
    case Repo.transaction(function) do
      {:ok, {:ok, value}} -> {:ok, value}
      {:ok, {:error, reason}} -> {:error, reason}
      {:ok, value} -> {:ok, value}
      {:error, reason} -> {:error, reason}
    end
  end

  defp after_verification({:ok, %{assurance: "AAL2"} = value}, user_id, _ip_address) do
    _ = RateLimiter.clear_user(user_id)
    {:ok, value}
  end

  defp after_verification({:error, :invalid_mfa_code} = error, user_id, ip_address) do
    _ = RateLimiter.record_failure(user_id, ip_address)
    error
  end

  defp after_verification(value, _user_id, _ip_address), do: value
end
