defmodule KeystonePhoenix.Auth.Oidc.Config do
  @moduledoc "OIDC 单 provider 配置和入口校验。"

  @required [
    :issuer,
    :authorization_endpoint,
    :token_endpoint,
    :jwks_uri,
    :client_id,
    :redirect_uri
  ]

  def enabled?, do: config()[:enabled] == true

  def config do
    Application.get_env(:keystone_phoenix, :oidc, %{})
    |> Map.new()
  end

  def validate do
    current = config()

    cond do
      not enabled?() -> {:error, :oidc_disabled}
      Enum.any?(@required, &blank?(current[&1])) -> {:error, :oidc_configuration}
      not valid_issuer?(current[:issuer]) -> {:error, :oidc_configuration}
      not valid_endpoint?(current[:authorization_endpoint]) -> {:error, :oidc_configuration}
      not valid_endpoint?(current[:token_endpoint]) -> {:error, :oidc_configuration}
      not valid_endpoint?(current[:jwks_uri]) -> {:error, :oidc_configuration}
      not valid_endpoint?(current[:redirect_uri]) -> {:error, :oidc_configuration}
      true -> {:ok, current}
    end
  end

  def code_ttl_seconds(config), do: Map.get(config, :code_ttl_seconds, 300)
  def http_client(config), do: Map.get(config, :http_client, KeystonePhoenix.Auth.Oidc.HttpClient)
  def auto_provision?(config), do: Map.get(config, :auto_provision, false) == true

  defp blank?(value), do: not (is_binary(value) and String.trim(value) != "")

  defp valid_issuer?(value) do
    case URI.parse(value) do
      %URI{scheme: scheme, host: host, query: nil, fragment: nil}
      when scheme in ["https", "http"] and is_binary(host) and host != "" ->
        scheme == "https" or host in ["localhost", "127.0.0.1", "::1"]

      _ ->
        false
    end
  end

  defp valid_endpoint?(value) do
    case URI.parse(value) do
      %URI{scheme: scheme, host: host, query: nil, fragment: nil}
      when scheme in ["https", "http"] and is_binary(host) and host != "" ->
        scheme == "https" or host in ["localhost", "127.0.0.1", "::1"]

      _ ->
        false
    end
  end
end
