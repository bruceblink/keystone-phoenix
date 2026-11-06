defmodule KeystonePhoenixWeb.AuthController do
  use KeystonePhoenixWeb, :controller

  plug KeystonePhoenixWeb.Plugs.Authenticate when action in [:current_user, :routers, :logout]

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

      {:error, :unavailable} ->
        render_error(conn, :unavailable)
    end
  end

  @doc "Registration remains disabled until an explicit registration policy is added."
  def register(conn, _params) do
    conn
    |> put_status(:not_implemented)
    |> json(ApiResponse.error(50101, "暂不支持用户注册"))
  end

  @doc "Authenticates a local username and password."
  def login(conn, %{"username" => username, "password" => password} = params) do
    case Auth.login(
           username,
           password,
           params["forceLogin"] == true,
           params["captchaCode"],
           params["captchaCodeKey"]
         ) do
      {:ok, tokens} ->
        Log.record_login(conn, username, 1, "登录成功")
        json(conn, ApiResponse.ok(token_to_map(tokens)))

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
    end
  end

  def login(conn, _params), do: render_error(conn, :invalid_credentials)

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

  defp render_error(conn, :invalid_credentials) do
    conn
    |> put_status(:unauthorized)
    |> json(ApiResponse.error(10002, "用户名或密码错误"))
  end

  defp render_error(conn, :captcha_required) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(ApiResponse.error(10205, "验证码为空"))
  end

  defp render_error(conn, :captcha_invalid) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(ApiResponse.error(10203, "验证码错误"))
  end

  defp render_error(conn, :captcha_expired) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(ApiResponse.error(10204, "验证码过期"))
  end

  defp render_error(conn, :invalid_refresh_token) do
    conn
    |> put_status(:unauthorized)
    |> json(ApiResponse.error(40102, "刷新令牌无效或已过期"))
  end

  defp render_error(conn, :already_logged_in) do
    conn
    |> put_status(:conflict)
    |> json(ApiResponse.error(10210, "该账号已经登录"))
  end

  defp render_error(conn, :unavailable) do
    conn
    |> put_status(:service_unavailable)
    |> json(ApiResponse.error(50301, "认证会话暂不可用"))
  end

  defp render_error(conn, :token_configuration) do
    conn
    |> put_status(:internal_server_error)
    |> json(ApiResponse.error(50001, "认证密钥配置无效"))
  end
end
