defmodule KeystonePhoenixWeb.OidcController do
  use KeystonePhoenixWeb, :controller

  alias KeystonePhoenix.Auth
  alias KeystonePhoenix.Auth.Oidc.{AuthorizationCode, Config, Identity, Provider, Verifier}
  alias KeystonePhoenix.Log
  alias KeystonePhoenixWeb.ApiResponse
  alias KeystonePhoenixWeb.AuthTokenResponse

  @session_key :keystone_oidc_pending

  @doc "创建 OIDC Authorization Code 请求并重定向到外部身份提供商。"
  def authorize(conn, params) do
    with {:ok, config} <- Config.validate(),
         :ok <- validate_client_request(params, config),
         state <- random_value(),
         nonce <- random_value(),
         verifier <- random_value(),
         challenge <- pkce_challenge(verifier),
         {:ok, redirect} <- authorization_redirect(config, state, nonce, challenge) do
      pending = %{
        "state" => state,
        "nonce" => nonce,
        "verifier" => verifier,
        "client_id" => config[:client_id],
        "redirect_uri" => config[:redirect_uri]
      }

      conn
      |> configure_session(renew: true)
      |> put_session(@session_key, pending)
      |> redirect(external: redirect)
    else
      {:error, reason} -> render_error(conn, reason)
    end
  end

  @doc "校验 state、PKCE、provider ID token 和外部 subject，然后创建本地会话。"
  def callback(conn, %{"code" => code, "state" => state}) do
    pending = get_session(conn, @session_key)
    conn = delete_session(conn, @session_key)

    with {:ok, config} <- Config.validate(),
         :ok <- validate_pending(pending, state, config),
         :ok <-
           AuthorizationCode.consume(code, %{
             provider: provider_key(config),
             client_id: config[:client_id],
             redirect_uri: config[:redirect_uri],
             state: state,
             ttl_seconds: Config.code_ttl_seconds(config)
           }),
         {:ok, id_token} <- Provider.exchange(code, pending["verifier"], config),
         {:ok, claims} <- Verifier.verify(id_token, config, pending["nonce"]),
         {:ok, user} <- Identity.resolve(claims, config),
         {:ok, tokens} <- Auth.login_oidc_user(user, "oidc") do
      Log.record_login(conn, user.username, 1, "OIDC 登录成功")
      json(conn, ApiResponse.ok(token_to_map(tokens)))
    else
      {:mfa_required, %{challenge: challenge, username: username}} ->
        render_mfa_required(conn, username, challenge)

      {:error, reason} ->
        render_error(conn, reason)
    end
  end

  def callback(conn, _params), do: render_error(conn, :invalid_external_identity)

  defp validate_client_request(params, config) do
    if params["client_id"] in [nil, config[:client_id]] and
         params["redirect_uri"] in [nil, config[:redirect_uri]] do
      :ok
    else
      {:error, :invalid_external_identity}
    end
  end

  defp validate_pending(pending, state, config) when is_map(pending) do
    if secure_equal?(pending["state"], state) and pending["client_id"] == config[:client_id] and
         pending["redirect_uri"] == config[:redirect_uri] and is_binary(pending["verifier"]) and
         is_binary(pending["nonce"]) do
      :ok
    else
      {:error, :invalid_external_identity}
    end
  end

  defp validate_pending(_, _, _), do: {:error, :invalid_external_identity}

  defp authorization_redirect(config, state, nonce, challenge) do
    query =
      URI.encode_query(%{
        "response_type" => "code",
        "client_id" => config[:client_id],
        "redirect_uri" => config[:redirect_uri],
        "scope" => Enum.join(config[:scopes] || ["openid", "profile", "email"], " "),
        "state" => state,
        "nonce" => nonce,
        "code_challenge" => challenge,
        "code_challenge_method" => "S256"
      })

    {:ok, config[:authorization_endpoint] <> "?" <> query}
  end

  defp random_value, do: :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)

  defp pkce_challenge(verifier),
    do: :crypto.hash(:sha256, verifier) |> Base.url_encode64(padding: false)

  defp secure_equal?(left, right) when is_binary(left) and is_binary(right) do
    byte_size(left) == byte_size(right) and Plug.Crypto.secure_compare(left, right)
  rescue
    _ -> false
  end

  defp secure_equal?(_, _), do: false

  defp provider_key(config), do: config[:issuer] |> String.trim() |> String.trim_trailing("/")

  defp token_to_map(tokens), do: AuthTokenResponse.to_map(tokens)

  defp render_error(conn, :oidc_disabled),
    do: error(conn, :authorization_unavailable, "OIDC 未启用", :service_unavailable)

  defp render_error(conn, :oidc_configuration),
    do: error(conn, :authorization_unavailable, "OIDC 配置无效", :service_unavailable)

  defp render_error(conn, :authorization_code_replayed),
    do: error(conn, :invalid_credential, "授权码已使用或已过期", :unauthorized)

  defp render_error(conn, :external_identity_unmapped),
    do: error(conn, :permission_denied, "外部身份未绑定本地用户", :forbidden)

  defp render_error(conn, :mfa_required),
    do: error(conn, :invalid_credential, "需要完成多因素认证", :unauthorized)

  defp render_error(conn, :mfa_enrollment_required),
    do: error(conn, :invalid_credential, "需要先完成多因素认证配置", :unauthorized)

  defp render_error(conn, :authorization_unavailable),
    do: error(conn, :authorization_unavailable, "外部认证服务暂不可用", :service_unavailable)

  defp render_error(conn, reason) do
    Log.record_login(conn, "oidc", 0, "OIDC 登录失败: #{error_message(reason)}")
    error(conn, :invalid_credential, "外部身份认证失败", :unauthorized)
  end

  defp error_message(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp error_message(_reason), do: "unknown"

  defp render_mfa_required(conn, username, challenge) do
    data =
      challenge
      |> Map.take([:id, :purpose, :client_id, :session_id, :context_hash, :expires_at])
      |> Map.put(:username, username)
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)
      |> Map.new()

    Log.record_login(conn, username, 0, "OIDC 登录需要多因素认证")

    conn
    |> put_status(:unauthorized)
    |> json(ApiResponse.error(:invalid_credential, "需要多因素认证", data))
  end

  defp error(conn, code, message, status),
    do: conn |> put_status(status) |> json(ApiResponse.error(code, message))
end
