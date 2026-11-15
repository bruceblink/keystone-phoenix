defmodule KeystonePhoenixWeb.Plugs.RequireMfaStepUp do
  @moduledoc "按账号 MFA 策略或 enforce 选项检查当前访问令牌的短时 AAL2 step-up 结果。"

  import Plug.Conn

  alias KeystonePhoenix.Auth.Mfa
  alias KeystonePhoenix.Auth.Token
  alias KeystonePhoenixWeb.ApiResponse

  def init(opts), do: Keyword.put_new(opts, :enforce, false)

  def call(conn, opts) do
    with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
         {:ok, claims} <- Token.verify(token, Token.access_type()),
         true <-
           claims["aal"] == "AAL2" or
             initial_enrollment?(conn, claims) or
             not required_step_up?(claims, opts) do
      conn
    else
      _ ->
        conn
        |> put_status(:forbidden)
        |> Phoenix.Controller.json(ApiResponse.error(:permission_denied, "MFA step-up required"))
        |> halt()
    end
  end

  # 未启用强制 MFA 的账号沿用 Native 的策略；enforce 用于必须升级认证的入口。
  defp required_step_up?(claims, opts) do
    Keyword.get(opts, :enforce, false) or
      case Mfa.status(claims["sub"]) do
        {:ok, %{required: true}} -> true
        {:ok, %{required: false}} -> false
        _ -> true
      end
  end

  defp initial_enrollment?(conn, claims) do
    conn.private[:phoenix_action] in [:begin_mfa_enrollment, :verify_mfa_enrollment] and
      match?({:ok, %{enabled: false}}, Mfa.status(claims["sub"]))
  end
end
