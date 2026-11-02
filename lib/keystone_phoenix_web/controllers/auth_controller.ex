defmodule KeystonePhoenixWeb.AuthController do
  use KeystonePhoenixWeb, :controller

  alias KeystonePhoenix.Auth
  alias KeystonePhoenix.Auth.Token
  alias KeystonePhoenixWeb.ApiResponse

  @doc "Returns the public key used to verify RS256 access tokens."
  def public_key(conn, _params) do
    json(conn, ApiResponse.ok(%{"publicKey" => Token.public_key_base64()}))
  end

  @doc "Authenticates a local username and password."
  def login(conn, %{"username" => username, "password" => password}) do
    case Auth.login(username, password) do
      {:ok, tokens} -> json(conn, ApiResponse.ok(token_to_map(tokens)))
      {:error, :invalid_credentials} -> render_error(conn, :invalid_credentials)
      {:error, :unavailable} -> render_error(conn, :unavailable)
      {:error, :token_configuration} -> render_error(conn, :token_configuration)
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

  defp render_error(conn, :invalid_refresh_token) do
    conn
    |> put_status(:unauthorized)
    |> json(ApiResponse.error(40102, "刷新令牌无效或已过期"))
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
