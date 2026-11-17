defmodule KeystonePhoenixWeb.Plugs.RequireMfaStepUp do
  @moduledoc "按账号 MFA 策略或 enforce 选项检查当前访问令牌的短时 AAL2 step-up 结果。"

  import Plug.Conn

  alias KeystonePhoenix.Auth.Mfa.RecentAuthentication
  alias KeystonePhoenix.Auth.Token
  alias KeystonePhoenixWeb.ApiResponse

  def init(opts), do: Keyword.put_new(opts, :enforce, false)

  def call(conn, opts) do
    with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
         {:ok, claims} <- Token.verify(token, Token.access_type()) do
      case RecentAuthentication.check(
             claims,
             Keyword.get(opts, :enforce, false),
             initial_enrollment_action?(conn)
           ) do
        :allowed -> conn
        :required -> step_up_required(conn)
        :unavailable -> authorization_unavailable(conn)
      end
    else
      _ -> step_up_required(conn)
    end
  end

  defp initial_enrollment_action?(conn) do
    conn.private[:phoenix_action] in [:begin_mfa_enrollment, :verify_mfa_enrollment]
  end

  defp step_up_required(conn) do
    conn
    |> put_status(:forbidden)
    |> Phoenix.Controller.json(ApiResponse.error(:mfa_step_up_required, "MFA step-up required"))
    |> halt()
  end

  defp authorization_unavailable(conn) do
    conn
    |> put_status(:service_unavailable)
    |> Phoenix.Controller.json(ApiResponse.error(:authorization_unavailable, "认证服务暂不可用"))
    |> halt()
  end
end
