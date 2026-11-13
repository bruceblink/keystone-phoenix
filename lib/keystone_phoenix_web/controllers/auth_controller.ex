defmodule KeystonePhoenixWeb.AuthController do
  use KeystonePhoenixWeb, :controller

  plug KeystonePhoenixWeb.Plugs.RejectApiKey

  plug KeystonePhoenixWeb.Plugs.Authenticate when action in [:current_user, :routers, :logout]

  plug KeystonePhoenixWeb.Plugs.Authenticate,
       [
         permissions: %{
           begin_mfa_enrollment: "mfa:manage",
           verify_mfa_enrollment: "mfa:manage",
           rotate_mfa_recovery_codes: "mfa:manage",
           set_mfa_policy: "mfa:manage",
           begin_mfa_step_up: "mfa:manage",
           verify_mfa_step_up: "mfa:manage"
         }
       ]
       when action in [
              :begin_mfa_enrollment,
              :verify_mfa_enrollment,
              :rotate_mfa_recovery_codes,
              :set_mfa_policy,
              :begin_mfa_step_up,
              :verify_mfa_step_up
            ]

  plug KeystonePhoenixWeb.Plugs.RequireMfaStepUp
       when action in [
              :begin_mfa_enrollment,
              :verify_mfa_enrollment,
              :rotate_mfa_recovery_codes,
              :set_mfa_policy
            ]

  plug KeystonePhoenixWeb.Plugs.RateLimit,
       [key: "getConfig", limit: 5, window: 10, scope: :global]
       when action in [:config]

  plug KeystonePhoenixWeb.Plugs.RateLimit,
       [key: "captchaImage", limit: 10, window: 10, scope: :ip]
       when action in [:captcha]

  plug KeystonePhoenixWeb.Plugs.RateLimit,
       [key: "rsa-public-key", limit: 60, window: 60, scope: :ip]
       when action in [:public_key]

  alias KeystonePhoenix.Auth
  alias KeystonePhoenix.Auth.Captcha
  alias KeystonePhoenix.Auth.LoginLimiter
  alias KeystonePhoenix.Auth.Mfa
  alias KeystonePhoenix.Auth.Token
  alias KeystonePhoenix.Config
  alias KeystonePhoenix.Dictionary
  alias KeystonePhoenix.Log
  alias KeystonePhoenix.Menu
  alias KeystonePhoenixWeb.ApiResponse

  @doc "Returns the public key used to verify RS256 access tokens."
  def public_key(conn, _params) do
    json(conn, ApiResponse.ok(%{"publicKey" => Token.public_key_base64()}))
  end

  @doc "Returns public login configuration and dictionary data."
  def config(conn, _params) do
    json(
      conn,
      ApiResponse.ok(%{
        "isCaptchaOn" => Config.get_config_value_by_key("sys.account.captchaOnOff") == "true",
        "dictionary" => %{
          "common.yesOrNo" => Dictionary.list_dict_data_by_type("common.yesOrNo"),
          "common.status" => Dictionary.list_dict_data_by_type("common.status")
        }
      })
    )
  end

  @doc "Returns a one-time captcha image when the database switch is enabled."
  def captcha(conn, _params) do
    case Captcha.generate() do
      {:ok, captcha} ->
        json(
          conn,
          ApiResponse.ok(%{
            "isCaptchaOn" => Captcha.enabled?(),
            "captchaCodeKey" => captcha.captcha_code_key,
            "captchaCodeImg" => captcha.captcha_code_img
          })
        )

      {:error, reason} when reason in [:capacity, :unavailable] ->
        render_error(conn, :unavailable)
    end
  end

  @doc "Registration remains disabled until an explicit registration policy is added."
  def register(conn, _params) do
    conn
    |> put_status(:not_implemented)
    |> json(ApiResponse.error(:validation_failed, "暂不支持用户注册"))
  end

  @doc "Authenticates a local username and password."
  def login(conn, %{"username" => username, "password" => password} = params) do
    case LoginLimiter.check_http(username, conn.remote_ip) do
      :allow ->
        case Auth.login_api(
               username,
               password,
               params["forceLogin"] == true,
               params["captchaCode"],
               params["captchaCodeKey"],
               params["clientId"] || "web"
             ) do
          {:ok, tokens} ->
            Log.record_login(conn, username, 1, "登录成功")
            json(conn, ApiResponse.ok(token_to_map(tokens)))

          {:mfa_required, challenge} ->
            Log.record_login(conn, username, 0, "需要二次认证")

            conn
            |> put_status(:unauthorized)
            |> json(
              ApiResponse.error(
                :invalid_credential,
                "需要二次认证",
                challenge_to_map(challenge)
              )
            )

          {:error, :invalid_credentials} ->
            Log.record_login(conn, username, 0, "用户名或密码错误")
            render_error(conn, :invalid_credentials)

          {:error, :captcha_required} ->
            Log.record_login(conn, username, 0, "验证码为空")
            render_error(conn, :captcha_required)

          {:error, :captcha_invalid} ->
            Log.record_login(conn, username, 0, "验证码错误")
            render_error(conn, :captcha_invalid)

          {:error, :captcha_expired} ->
            Log.record_login(conn, username, 0, "验证码过期")
            render_error(conn, :captcha_expired)

          {:error, :already_logged_in} ->
            Log.record_login(conn, username, 0, "该账号已经登录")
            render_error(conn, :already_logged_in)

          {:error, :unavailable} ->
            Log.record_login(conn, username, 0, "认证会话暂不可用")
            render_error(conn, :unavailable)

          {:error, :token_configuration} ->
            Log.record_login(conn, username, 0, "认证密钥配置无效")
            render_error(conn, :token_configuration)

          {:error, :mfa_enrollment_required} ->
            render_mfa_error(conn, :mfa_enrollment_required)

          {:error, :validation_failed} ->
            render_mfa_error(conn, :validation_failed)
        end

      {:deny, retry_after} ->
        Log.record_login(conn, username, 0, "登录尝试过于频繁")

        conn
        |> put_resp_header("retry-after", Integer.to_string(retry_after))
        |> render_error(:rate_limited)

      {:error, reason} when reason in [:capacity, :unavailable] ->
        Log.record_login(conn, username, 0, "限流服务暂不可用")
        render_error(conn, :rate_limited_unavailable)
    end
  end

  def login(conn, _params), do: render_error(conn, :invalid_credentials)

  @doc "Completes a public login MFA challenge and creates a session."
  def verify_mfa(
        conn,
        %{"username" => username, "challengeId" => challenge_id, "code" => code} = params
      )
      when is_binary(username) and is_binary(challenge_id) and is_binary(code) do
    case Auth.complete_mfa_login(
           username,
           challenge_id,
           params["clientId"] || "web",
           code,
           params["forceLogin"] == true,
           conn.remote_ip
         ) do
      {:ok, %{tokens: tokens, verification: verification}} ->
        data =
          token_to_map(tokens)
          |> Map.put("authenticationLevel", verification.assurance)
          |> Map.put("amr", verification.amr)

        json(conn, ApiResponse.ok(data))

      {:error, reason} ->
        render_mfa_error(conn, reason)
    end
  end

  def verify_mfa(conn, _params), do: render_mfa_error(conn, :validation_failed)

  @doc "Starts TOTP enrollment for the current authenticated session."
  def begin_mfa_enrollment(conn, _params) do
    with {:ok, context} <- current_session_context(conn),
         {:ok, enrollment} <-
           safe_mfa(fn ->
             Mfa.begin_enrollment(
               context.user.user_id,
               context.user.username,
               context.client_id,
               context.session_id
             )
           end) do
      conn
      |> put_status(:created)
      |> json(ApiResponse.ok(enrollment_to_map(enrollment)))
    else
      {:error, reason} -> render_mfa_error(conn, reason)
    end
  end

  @doc "Verifies the TOTP enrollment and returns the one-time recovery codes."
  def verify_mfa_enrollment(
        conn,
        %{"challengeId" => challenge_id, "code" => code}
      )
      when is_binary(challenge_id) and is_binary(code) do
    with {:ok, context} <- current_session_context(conn),
         {:ok, verification} <-
           safe_mfa(fn ->
             Mfa.verify_enrollment(
               context.user.user_id,
               challenge_id,
               context.client_id,
               context.session_id,
               code,
               conn.remote_ip
             )
           end) do
      data =
        verification
        |> Map.take([:assurance, :amr, :recovery_codes])
        |> Map.new(fn
          {:assurance, value} -> {"authenticationLevel", value}
          {:amr, value} -> {"amr", value}
          {:recovery_codes, value} -> {"recoveryCodes", value}
        end)

      json(conn, ApiResponse.ok(data))
    else
      {:error, reason} -> render_mfa_error(conn, reason)
    end
  end

  def verify_mfa_enrollment(conn, _params),
    do: render_mfa_error(conn, :validation_failed)

  @doc "Rotates recovery codes after verifying the current password."
  def rotate_mfa_recovery_codes(conn, %{"currentPassword" => current_password})
      when is_binary(current_password) and current_password != "" do
    with {:ok, context} <- current_session_context(conn),
         {:ok, recovery_codes} <-
           safe_mfa(fn -> Auth.rotate_mfa_recovery_codes(context.user, current_password) end) do
      json(conn, ApiResponse.ok(%{"recoveryCodes" => recovery_codes}))
    else
      {:error, reason} -> render_mfa_error(conn, reason)
    end
  end

  def rotate_mfa_recovery_codes(conn, _params),
    do: render_mfa_error(conn, :validation_failed)

  @doc "Sets a user's required MFA policy and revokes sessions after the change."
  def set_mfa_policy(conn, %{"user_id" => user_id, "required" => required})
      when is_boolean(required) do
    case Auth.set_mfa_policy(user_id, required) do
      {:ok, data} -> json(conn, ApiResponse.ok(data))
      {:error, reason} -> render_mfa_error(conn, reason)
    end
  end

  def set_mfa_policy(conn, _params), do: render_mfa_error(conn, :validation_failed)

  @doc "Creates a current-session-bound step-up MFA challenge."
  def begin_mfa_step_up(conn, params) do
    with {:ok, context} <- current_session_context(conn),
         {:ok, challenge} <-
           safe_mfa(fn ->
             Mfa.begin_step_up(
               context.user.user_id,
               context.client_id,
               context.session_id,
               params["contextHash"]
             )
           end) do
      conn
      |> put_status(:created)
      |> json(ApiResponse.ok(challenge_to_map(challenge)))
    else
      {:error, reason} -> render_mfa_error(conn, reason)
    end
  end

  @doc "Verifies a current-session-bound step-up MFA challenge."
  def verify_mfa_step_up(
        conn,
        %{"challengeId" => challenge_id, "code" => code}
      )
      when is_binary(challenge_id) and is_binary(code) do
    with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
         {:ok, result} <-
           safe_mfa(fn ->
             Auth.complete_mfa_step_up(token, challenge_id, code, conn.remote_ip)
           end) do
      json(
        conn,
        ApiResponse.ok(%{
          "accessToken" => result.token,
          "expiresIn" => result.expires_in,
          "authenticationLevel" => result.authentication_level,
          "amr" => result.amr
        })
      )
    else
      {:error, reason} -> render_mfa_error(conn, reason)
    end
  end

  def verify_mfa_step_up(conn, _params),
    do: render_mfa_error(conn, :validation_failed)

  @doc "Rotates a refresh token and returns a new token pair."
  def refresh(conn, %{"refreshToken" => refresh_token}) do
    case Auth.refresh(refresh_token) do
      {:ok, tokens} -> json(conn, ApiResponse.ok(token_to_map(tokens)))
      {:error, :invalid_refresh_token} -> render_error(conn, :invalid_refresh_token)
      {:error, :unavailable} -> render_error(conn, :unavailable)
    end
  end

  def refresh(conn, _params), do: render_error(conn, :invalid_refresh_token)

  @doc "Revokes a refresh token session."
  def logout_refresh_token(conn, %{"refreshToken" => refresh_token}) do
    Auth.logout(refresh_token)
    json(conn, ApiResponse.ok())
  end

  def logout_refresh_token(conn, _params), do: json(conn, ApiResponse.ok())

  @doc "Revokes the current access token's refresh session."
  def logout(conn, _params) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] -> Auth.logout_access(token)
      _ -> :ok
    end

    json(conn, ApiResponse.ok())
  end

  @doc "Returns the current authenticated user."
  def current_user(conn, _params) do
    json(conn, ApiResponse.ok(Auth.current_login_user(conn.assigns.current_user)))
  end

  @doc "Returns the authenticated user's menu router tree."
  def routers(conn, _params) do
    json(conn, ApiResponse.ok(Menu.routers_for_user(conn.assigns.current_user)))
  end

  defp token_to_map(tokens) do
    %{
      "token" => tokens.token,
      "refreshToken" => tokens.refresh_token,
      "expiresIn" => tokens.expires_in,
      "refreshExpiresIn" => tokens.refresh_expires_in,
      "currentUser" => tokens.current_user
    }
  end

  defp current_session_context(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] -> Auth.session_context(token)
      _ -> {:error, :invalid_token}
    end
  end

  defp safe_mfa(function) do
    function.()
  rescue
    _error -> {:error, :unavailable}
  end

  defp enrollment_to_map(enrollment) do
    %{
      "challengeId" => enrollment.challenge_id,
      "factorId" => enrollment.factor_id,
      "secret" => enrollment.secret,
      "otpauthUri" => enrollment.otpauth_uri,
      "expiresAt" => DateTime.to_iso8601(enrollment.expires_at)
    }
  end

  defp challenge_to_map(challenge) do
    %{
      "challengeId" => Map.get(challenge, :challenge_id) || Map.get(challenge, :id),
      "purpose" => Map.get(challenge, :purpose),
      "clientId" => Map.get(challenge, :client_id),
      "sessionId" => Map.get(challenge, :session_id),
      "contextHash" => Map.get(challenge, :context_hash),
      "expiresAt" => Map.get(challenge, :expires_at) |> DateTime.to_iso8601()
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp render_mfa_error(conn, :invalid_token) do
    conn
    |> put_status(:unauthorized)
    |> json(ApiResponse.error(:session_revoked, "登录状态已失效"))
  end

  defp render_mfa_error(conn, reason)
       when reason in [
              :invalid_mfa_code,
              :invalid_challenge,
              :invalid_credentials,
              :user_not_found
            ] do
    conn
    |> put_status(:unauthorized)
    |> json(ApiResponse.error(:invalid_credential, "MFA 验证失败"))
  end

  defp render_mfa_error(conn, reason)
       when reason in [:mfa_not_enrolled, :mfa_already_enabled, :mfa_enrollment_required] do
    conn
    |> put_status(:unprocessable_entity)
    |> json(ApiResponse.error(:validation_failed, "MFA 状态不满足当前操作"))
  end

  defp render_mfa_error(conn, :already_logged_in),
    do: render_error(conn, :already_logged_in)

  defp render_mfa_error(conn, :rate_limited) do
    conn
    |> put_status(:too_many_requests)
    |> json(ApiResponse.error(:validation_failed, "MFA 验证次数过多，请稍后重试"))
  end

  defp render_mfa_error(conn, reason) when reason in [:unavailable, :authorization_unavailable],
    do: render_error(conn, :unavailable)

  defp render_mfa_error(conn, :validation_failed),
    do: render_error(conn, :validation_failed)

  defp render_mfa_error(conn, _reason), do: render_error(conn, :unavailable)

  defp render_error(conn, :invalid_credentials) do
    conn
    |> put_status(:unauthorized)
    |> json(ApiResponse.error(:invalid_credential, "用户名或密码错误"))
  end

  defp render_error(conn, :captcha_required) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(ApiResponse.error(:validation_failed, "验证码为空"))
  end

  defp render_error(conn, :captcha_invalid) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(ApiResponse.error(:validation_failed, "验证码错误"))
  end

  defp render_error(conn, :captcha_expired) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(ApiResponse.error(:validation_failed, "验证码过期"))
  end

  defp render_error(conn, :validation_failed) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(ApiResponse.error(:validation_failed, "请求参数无效"))
  end

  defp render_error(conn, :invalid_refresh_token) do
    conn
    |> put_status(:unauthorized)
    |> json(ApiResponse.error(:session_revoked, "刷新令牌无效或已过期"))
  end

  defp render_error(conn, :already_logged_in) do
    conn
    |> put_status(:conflict)
    |> json(ApiResponse.error(:validation_failed, "该账号已经登录"))
  end

  defp render_error(conn, :unavailable) do
    conn
    |> put_status(:service_unavailable)
    |> json(ApiResponse.error(:authorization_unavailable, "认证会话暂不可用"))
  end

  defp render_error(conn, :token_configuration) do
    conn
    |> put_status(:service_unavailable)
    |> json(ApiResponse.error(:authorization_unavailable, "认证密钥配置无效"))
  end

  defp render_error(conn, :rate_limited) do
    conn
    |> put_status(:too_many_requests)
    |> json(ApiResponse.error(:validation_failed, "登录尝试过于频繁，请稍后再试"))
  end

  defp render_error(conn, :rate_limited_unavailable) do
    conn
    |> put_status(:service_unavailable)
    |> json(ApiResponse.error(:authorization_unavailable, "限流服务暂不可用，请稍后重试"))
  end
end
