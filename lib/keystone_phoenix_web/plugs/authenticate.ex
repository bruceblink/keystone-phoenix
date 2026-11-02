defmodule KeystonePhoenixWeb.Plugs.Authenticate do
  @moduledoc "Authenticates a Bearer access token and assigns the current user."

  import Plug.Conn

  alias KeystonePhoenix.Auth
  alias KeystonePhoenixWeb.ApiResponse

  def init(opts), do: opts

  def call(conn, _opts) do
    with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
         {:ok, user} <- Auth.authenticate_access_token(token) do
      assign(conn, :current_user, user)
    else
      _ ->
        conn
        |> put_status(:unauthorized)
        |> Phoenix.Controller.json(ApiResponse.error(40101, "登录状态已过期"))
        |> halt()
    end
  end
end
