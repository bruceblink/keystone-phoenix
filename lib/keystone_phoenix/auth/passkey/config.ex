defmodule KeystonePhoenix.Auth.Passkey.Config do
  @moduledoc """
  验证 WebAuthn relying party 配置。

  RP ID 和 origin 只来自受控配置。请求头不能覆盖这两个值。
  """

  @verification_modes ["required", "preferred", "discouraged"]

  def enabled?, do: config()[:enabled] == true

  def config do
    Application.get_env(:keystone_phoenix, :passkey, []) |> Map.new()
  end

  def validate do
    current = config()

    cond do
      not enabled?() ->
        {:error, :passkey_disabled}

      not valid_rp_id?(current[:rp_id]) ->
        {:error, :passkey_configuration}

      not valid_origin?(current[:origin]) ->
        {:error, :passkey_configuration}

      not rp_matches_origin?(current[:rp_id], current[:origin]) ->
        {:error, :passkey_configuration}

      current[:user_verification] not in @verification_modes ->
        {:error, :passkey_configuration}

      not valid_ttl?(current[:challenge_ttl_seconds]) ->
        {:error, :passkey_configuration}

      true ->
        {:ok, current}
    end
  end

  def challenge_ttl_seconds(config), do: config[:challenge_ttl_seconds] || 120

  defp valid_rp_id?(value) when is_binary(value) do
    value != "" and not String.contains?(value, ["/", ":", " ", "\\"])
  end

  defp valid_rp_id?(_value), do: false

  defp valid_origin?(value) when is_binary(value) do
    case URI.parse(value) do
      %URI{scheme: "https", host: host, path: path, query: nil, fragment: nil}
      when is_binary(host) and host != "" and path in [nil, ""] ->
        true

      %URI{scheme: "http", host: host, path: path, query: nil, fragment: nil}
      when host in ["localhost", "127.0.0.1", "::1"] and path in [nil, ""] ->
        true

      _ ->
        false
    end
  end

  defp valid_origin?(_value), do: false

  defp rp_matches_origin?(rp_id, origin) when is_binary(rp_id) and is_binary(origin) do
    host = URI.parse(origin).host
    is_binary(host) and (host == rp_id or String.ends_with?(host, "." <> rp_id))
  end

  defp rp_matches_origin?(_rp_id, _origin), do: false

  defp valid_ttl?(value), do: is_integer(value) and value in 30..300
end
