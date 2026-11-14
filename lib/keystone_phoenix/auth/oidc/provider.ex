defmodule KeystonePhoenix.Auth.Oidc.Provider do
  @moduledoc "执行 OIDC authorization code 到本地会话的交换。"

  alias KeystonePhoenix.Auth.Oidc.Config

  def exchange(code, verifier, config) do
    form =
      URI.encode_query(%{
        "grant_type" => "authorization_code",
        "code" => code,
        "redirect_uri" => config[:redirect_uri],
        "client_id" => config[:client_id],
        "client_secret" => config[:client_secret] || "",
        "code_verifier" => verifier
      })

    headers = [{"content-type", "application/x-www-form-urlencoded"}]

    with {:ok, 200, body} <-
           apply(Config.http_client(config), :post, [config[:token_endpoint], form, headers]),
         {:ok, %{"id_token" => id_token}} <- Jason.decode(body),
         true <- is_binary(id_token) do
      {:ok, id_token}
    else
      _ -> {:error, :external_token_exchange_failed}
    end
  rescue
    _ -> {:error, :external_token_exchange_failed}
  end
end
