defmodule KeystonePhoenixWeb.JwkController do
  use KeystonePhoenixWeb, :controller

  alias KeystonePhoenix.Auth.Token
  alias KeystonePhoenixWeb.ApiResponse

  @doc "使用标准 JWK Set 结构发布签名公钥。"
  def show(conn, _params) do
    case Token.public_jwk_set() do
      {:ok, jwk_set} -> json(conn, jwk_set)
      {:error, _reason} -> unavailable(conn)
    end
  rescue
    _error -> unavailable(conn)
  end

  defp unavailable(conn) do
    conn
    |> put_status(:service_unavailable)
    |> json(ApiResponse.error(:authorization_unavailable, "签名公钥暂不可用"))
  end
end
