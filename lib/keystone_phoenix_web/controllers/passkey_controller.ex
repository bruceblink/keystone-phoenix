defmodule KeystonePhoenixWeb.PasskeyController do
  use KeystonePhoenixWeb, :controller

  alias KeystonePhoenix.Auth
  alias KeystonePhoenix.Auth.Passkey.{Accounts, Challenge, Config}
  alias KeystonePhoenix.Log
  alias KeystonePhoenixWeb.ApiResponse

  @registration_key :keystone_passkey_registration
  @authentication_key :keystone_passkey_authentication

  @doc "为已经完成 step-up 的本地用户创建 passkey 注册 challenge。"
  def registration_challenge(conn, _params) do
    with {:ok, config} <- Config.validate(),
         {:ok, account} <- Accounts.for_user(conn.assigns.current_user),
         challenge <-
           Ithibati.Identity.Passkeys.registration_challenge(
             config[:rp_id],
             config[:origin],
             user_verification: config[:user_verification],
             seconds: Config.challenge_ttl_seconds(config)
           ),
         {:ok, challenge_id} <- Challenge.issue(challenge) do
      conn
      |> put_session(@registration_key, %{
        "challenge" => Ithibati.Identity.Passkeys.retain_challenge(challenge),
        "accountId" => account.id
      })
      |> json(
        ApiResponse.ok(%{
          "challengeId" => challenge_id,
          "options" =>
            Ithibati.Identity.Passkeys.registration_options(challenge, account,
              rp_name: config[:rp_name]
            )
        })
      )
    else
      {:error, reason} -> render_error(conn, reason)
    end
  rescue
    _ -> render_error(conn, :passkey_unavailable)
  end

  @doc "消费注册 challenge，验证浏览器凭据并保存 passkey。"
  def registration(conn, %{"challengeId" => challenge_id, "credential" => credential} = params) do
    {conn, pending} = take_session(conn, @registration_key)

    with {:ok, config} <- Config.validate(),
         {:ok, retained, account_id} <- pending_challenge(pending, challenge_id, :attestation),
         :ok <- Challenge.consume(retained),
         :ok <- same_account?(account_id, conn.assigns.current_user),
         challenge <- restore(retained, config),
         {:ok, key_attrs} <- safe_verify_registration(credential, challenge),
         {:ok, account} <- Accounts.by_id(account_id),
         {:ok, _key} <- add_key(account, key_attrs, params["label"]) do
      Log.record_login(conn, conn.assigns.current_user.username, 1, "Passkey 注册成功")
      json(conn, ApiResponse.ok(%{"registered" => true}))
    else
      {:error, reason} -> render_error(conn, reason)
    end
  rescue
    _ -> render_error(conn, :invalid_credential)
  end

  def registration(conn, _params), do: render_error(conn, :validation_failed)

  @doc "为无状态 passkey 登录创建 challenge。"
  def authentication_challenge(conn, _params) do
    with {:ok, config} <- Config.validate(),
         {:ok, challenge} <-
           safe_authentication_challenge(config),
         {:ok, challenge_id} <- Challenge.issue(challenge) do
      conn
      |> put_session(@authentication_key, %{
        "challenge" => Ithibati.Identity.Passkeys.retain_challenge(challenge)
      })
      |> json(
        ApiResponse.ok(%{
          "challengeId" => challenge_id,
          "options" => Ithibati.Identity.Passkeys.authentication_options(challenge)
        })
      )
    else
      {:error, reason} -> render_error(conn, reason)
    end
  rescue
    _ -> render_error(conn, :passkey_unavailable)
  end

  @doc "消费登录 challenge，验证 passkey 并签发本地 AAL2 会话。"
  def authentication(conn, %{"challengeId" => challenge_id, "credential" => credential}) do
    {conn, pending} = take_session(conn, @authentication_key)

    with {:ok, config} <- Config.validate(),
         {:ok, retained, _account_id} <- pending_challenge(pending, challenge_id, :authentication),
         :ok <- Challenge.consume(retained),
         challenge <- restore(retained, config),
         {:ok, account} <- safe_verify_authentication(credential, challenge),
         {:ok, user} <- Accounts.local_user(account),
         {:ok, tokens} <- Auth.login_passkey_user(user.user_id, "passkey") do
      Log.record_login(conn, user.username, 1, "Passkey 登录成功")
      json(conn, ApiResponse.ok(token_to_map(tokens)))
    else
      {:error, reason} -> render_error(conn, reason)
      _ -> render_error(conn, :invalid_credential)
    end
  rescue
    _ -> render_error(conn, :invalid_credential)
  end

  def authentication(conn, _params), do: render_error(conn, :validation_failed)

  defp safe_authentication_challenge(config) do
    case Ithibati.Identity.Passkeys.authentication_challenge(
           config[:rp_id],
           config[:origin],
           user_verification: config[:user_verification],
           seconds: Config.challenge_ttl_seconds(config)
         ) do
      {:ok, challenge} -> {:ok, challenge}
      {:error, :no_credentials} -> {:error, :invalid_credential}
    end
  rescue
    _ -> {:error, :passkey_unavailable}
  end

  defp safe_verify_registration(credential, challenge) do
    case Ithibati.Identity.Passkeys.verify_registration(credential, challenge) do
      {:ok, attrs} -> {:ok, attrs}
      {:error, _reason} -> {:error, :invalid_credential}
    end
  rescue
    _ -> {:error, :invalid_credential}
  end

  defp safe_verify_authentication(credential, challenge) do
    case Ithibati.Identity.Passkeys.verify_authentication(credential, challenge) do
      {:ok, account} -> {:ok, account}
      {:error, _reason} -> {:error, :invalid_credential}
    end
  rescue
    _ -> {:error, :invalid_credential}
  end

  defp add_key(account, attrs, label),
    do:
      Ithibati.Identity.Passkeys.add_key(
        account,
        Ithibati.Identity.Passkeys.key_attrs(attrs, label)
      )

  defp same_account?(account_id, user) do
    case Accounts.for_user(user) do
      {:ok, %{id: ^account_id}} -> :ok
      _ -> {:error, :permission_denied}
    end
  end

  defp restore(retained, config) do
    Ithibati.Identity.Passkeys.restore_challenge(
      Map.take(retained, [:type, :bytes, :issued_at, :rp_id, :origin]),
      user_verification: config[:user_verification],
      seconds: Config.challenge_ttl_seconds(config)
    )
  end

  defp take_session(conn, key) do
    {get_session(conn, key), delete_session(conn, key)}
    |> then(fn {pending, conn} -> {conn, pending} end)
  end

  defp pending_challenge(%{"challenge" => retained} = pending, challenge_id, type)
       when is_map(retained) do
    if retained.type == type and Challenge.id(retained) == challenge_id do
      {:ok, retained, pending["accountId"]}
    else
      {:error, :passkey_challenge_invalid}
    end
  end

  defp pending_challenge(_pending, _challenge_id, _type),
    do: {:error, :passkey_challenge_invalid}

  defp token_to_map(tokens) do
    KeystonePhoenixWeb.AuthTokenResponse.to_map(tokens)
    |> Map.merge(%{"authenticationLevel" => "AAL2", "amr" => ["passkey"]})
  end

  defp render_error(conn, :passkey_disabled),
    do: error(conn, :authorization_unavailable, "Passkey 认证未启用", :service_unavailable)

  defp render_error(conn, :passkey_configuration),
    do: error(conn, :authorization_unavailable, "Passkey 配置无效", :service_unavailable)

  defp render_error(conn, :passkey_unavailable),
    do: error(conn, :authorization_unavailable, "Passkey 服务暂不可用", :service_unavailable)

  defp render_error(conn, :passkey_challenge_invalid),
    do: error(conn, :invalid_credential, "Passkey challenge 已失效", :unauthorized)

  defp render_error(conn, :invalid_credential),
    do: error(conn, :invalid_credential, "Passkey 验证失败", :unauthorized)

  defp render_error(conn, :permission_denied),
    do: error(conn, :permission_denied, "没有操作权限", :forbidden)

  defp render_error(conn, :validation_failed),
    do: error(conn, :validation_failed, "请求参数无效", :bad_request)

  defp render_error(conn, _reason),
    do: error(conn, :authorization_unavailable, "Passkey 认证服务暂不可用", :service_unavailable)

  defp error(conn, code, message, status),
    do: conn |> put_status(status) |> json(ApiResponse.error(code, message))
end
