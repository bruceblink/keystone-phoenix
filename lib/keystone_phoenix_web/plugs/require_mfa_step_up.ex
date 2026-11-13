defmodule KeystonePhoenixWeb.Plugs.RequireMfaStepUp do
  @moduledoc "要求当前访问令牌携带短时 AAL2 step-up 认证结果。"

  import Plug.Conn

  alias KeystonePhoenix.Auth.Mfa
  alias KeystonePhoenix.Auth.Token
  alias KeystonePhoenixWeb.ApiResponse

  def init(opts), do: opts

  def call(conn, _opts) do
    with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
         {:ok, claims} <- Token.verify(token, Token.access_type()),
         true <- claims["aal"] == "AAL2" or initial_enrollment?(conn, claims) do
      conn
    else
      _ ->
        conn
        |> put_status(:forbidden)
        |> Phoenix.Controller.json(ApiResponse.error(:permission_denied, "需要二次认证"))
        |> halt()
    end
  end

  defp initial_enrollment?(conn, claims) do
    conn.private[:phoenix_action] in [:begin_mfa_enrollment, :verify_mfa_enrollment] and
      match?({:ok, %{enabled: false}}, Mfa.status(claims["sub"]))
  end
end
