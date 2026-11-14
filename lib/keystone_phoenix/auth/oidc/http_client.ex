defmodule KeystonePhoenix.Auth.Oidc.HttpClient do
  @moduledoc "OIDC token 和 JWKS 请求的标准库 HTTP 客户端。"

  @timeout 5_000

  def get(url) when is_binary(url), do: request(:get, url, [], "")

  def post(url, form, headers) when is_binary(url) and is_binary(form) and is_list(headers) do
    request(:post, url, headers, form)
  end

  defp request(:get, url, headers, _body) do
    _ = Application.ensure_all_started(:inets)
    _ = Application.ensure_all_started(:ssl)

    request =
      {String.to_charlist(url),
       Enum.map(headers, fn {name, value} ->
         {String.to_charlist(name), String.to_charlist(value)}
       end)}

    do_request(:get, request)
  end

  defp request(:post, url, headers, body) do
    _ = Application.ensure_all_started(:inets)
    _ = Application.ensure_all_started(:ssl)

    request = {
      String.to_charlist(url),
      Enum.map(headers, fn {name, value} ->
        {String.to_charlist(name), String.to_charlist(value)}
      end),
      ~c"application/x-www-form-urlencoded",
      String.to_charlist(body)
    }

    do_request(:post, request)
  end

  defp do_request(method, request) do
    ssl_options = [verify: :verify_peer, cacerts: :public_key.cacerts_get()]
    options = [timeout: @timeout, connect_timeout: @timeout, ssl: ssl_options]

    case :httpc.request(method, request, options, body_format: :binary) do
      {:ok, {{_http, status, _reason}, _headers, response}} -> {:ok, status, response}
      {:error, _reason} -> {:error, :oidc_provider_unavailable}
    end
  rescue
    _ -> {:error, :oidc_provider_unavailable}
  end
end
