defmodule KeystonePhoenixWeb.Plugs.Authenticate do
  @moduledoc "Authenticates a Bearer access token and assigns the current user."

  import Plug.Conn

  alias KeystonePhoenix.Auth
  alias KeystonePhoenixWeb.ApiResponse

  def init(opts), do: opts

  def call(conn, opts) do
    with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
         {:ok, user} <- Auth.authenticate_access_token(token),
         :ok <- authorize(user, opts) do
      assign(conn, :current_user, user)
    else
      {:error, :forbidden} ->
        conn
        |> put_status(:forbidden)
        |> Phoenix.Controller.json(ApiResponse.error(40301, "需要管理员权限"))
        |> halt()

      _ ->
        conn
        |> put_status(:unauthorized)
        |> Phoenix.Controller.json(ApiResponse.error(40101, "登录状态已过期"))
        |> halt()
    end
  end

  defp authorize(user, opts) do
    if Keyword.get(opts, :admin, false) and not Map.get(user, :is_admin, false) do
      {:error, :forbidden}
    else
      :ok
    end
  end
end
