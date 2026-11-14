defmodule KeystonePhoenix.Auth.Oidc.Verifier do
  @moduledoc "验证 OIDC ID token 的签名和标准声明。"

  alias KeystonePhoenix.Auth.Oidc.Config

  def verify(id_token, config, nonce) when is_binary(id_token) and is_map(config) do
    with {:ok, header} <- decode_part(id_token, 0),
         "RS256" <- header["alg"],
         kid when is_binary(kid) <- header["kid"],
         {:ok, jwks} <- fetch_jwks(config),
         {:ok, jwk} <- find_key(jwks, kid),
         {true, jwt, _jws} <- JOSE.JWT.verify_strict(JOSE.JWK.from_map(jwk), ["RS256"], id_token),
         {_modules, claims} <- JOSE.JWT.to_map(jwt),
         :ok <- validate_claims(claims, config, nonce) do
      {:ok, claims}
    else
      _ -> {:error, :invalid_external_identity}
    end
  rescue
    _ -> {:error, :invalid_external_identity}
  end

  defp fetch_jwks(config) do
    case apply(Config.http_client(config), :get, [config[:jwks_uri]]) do
      {:ok, 200, body} ->
        case Jason.decode(body) do
          {:ok, %{"keys" => keys}} when is_list(keys) -> {:ok, keys}
          _ -> {:error, :invalid_jwks}
        end

      _ ->
        {:error, :jwks_unavailable}
    end
  end

  defp find_key(keys, kid) do
    case Enum.find(keys, &(&1["kid"] == kid and &1["kty"] == "RSA")) do
      nil -> {:error, :unknown_kid}
      key -> {:ok, key}
    end
  end

  defp validate_claims(claims, config, nonce) do
    now = System.system_time(:second)
    issuer = config[:issuer]
    audience = claims["aud"]
    expected_audience = config[:audience] || config[:client_id]

    cond do
      claims["iss"] != issuer ->
        {:error, :issuer_mismatch}

      not audience_matches?(audience, expected_audience, claims["azp"]) ->
        {:error, :audience_mismatch}

      claims["nonce"] != nonce ->
        {:error, :nonce_mismatch}

      not is_binary(claims["sub"]) or String.trim(claims["sub"]) == "" ->
        {:error, :subject_missing}

      not is_integer(claims["exp"]) or claims["exp"] <= now ->
        {:error, :token_expired}

      not is_integer(claims["iat"]) or claims["iat"] > now + 60 ->
        {:error, :token_time_invalid}

      true ->
        :ok
    end
  end

  defp audience_matches?(audience, expected, _azp) when is_binary(audience),
    do: audience == expected

  defp audience_matches?([audience], expected, _azp), do: audience == expected

  defp audience_matches?(audience, expected, azp) when is_list(audience),
    do: expected in audience and azp == expected

  defp audience_matches?(_, _, _), do: false

  defp decode_part(token, index) do
    case String.split(token, ".") do
      parts when length(parts) == 3 ->
        case Base.url_decode64(Enum.at(parts, index), padding: false) do
          {:ok, payload} -> Jason.decode(payload)
          _ -> {:error, :invalid_token}
        end

      _ ->
        {:error, :invalid_token}
    end
  end
end
