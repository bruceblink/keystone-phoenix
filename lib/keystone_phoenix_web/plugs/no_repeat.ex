defmodule KeystonePhoenixWeb.Plugs.NoRepeat do
  @moduledoc "Blocks repeated authenticated submissions during a short interval."

  import Plug.Conn

  alias KeystonePhoenix.RateLimiter
  alias KeystonePhoenixWeb.ApiResponse

  def init(opts), do: opts

  def call(conn, opts) do
    case conn.assigns[:current_user] do
      %{user_id: user_id} -> check(conn, user_id, opts)
      _user -> conn
    end
  end

  defp check(conn, user_id, opts) do
    action = conn.private[:phoenix_action] || "unknown"
    key = "repeat:#{conn.request_path}:#{action}:#{user_id}"
    interval = Keyword.get(opts, :interval, 60)

    case RateLimiter.check(key, 1, interval) do
      :allow ->
        conn

      {:deny, retry_after} ->
        conn
        |> put_resp_header("retry-after", Integer.to_string(retry_after))
        |> put_status(:too_many_requests)
        |> Phoenix.Controller.json(ApiResponse.error(42902, "请勿重复提交"))
        |> halt()
    end
  end
end
