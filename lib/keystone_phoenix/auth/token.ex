defmodule KeystonePhoenix.Auth.Token do
  @moduledoc "RS256 access and refresh token handling."

  @access_type "access"
  @refresh_type "refresh"
  @key_cache_key {__MODULE__, :private_jwk}
  @public_key_cache_key {__MODULE__, :public_jwk}

  @spec access_type() :: String.t()
  def access_type, do: @access_type

  @spec refresh_type() :: String.t()
  def refresh_type, do: @refresh_type

  @spec access_ttl() :: pos_integer()
  def access_ttl, do: Application.get_env(:keystone_phoenix, :jwt_access_ttl, 1800)

  @spec refresh_ttl() :: pos_integer()
  def refresh_ttl, do: Application.get_env(:keystone_phoenix, :jwt_refresh_ttl, 604_800)

  @spec issue(map(), String.t()) :: {:ok, map()} | {:error, term()}
  def issue(user, token_type) when token_type in [@access_type, @refresh_type] do
    now = System.system_time(:second)
    ttl = if token_type == @access_type, do: access_ttl(), else: refresh_ttl()
    jti = Ecto.UUID.generate()

    claims = %{
      "iss" => Application.get_env(:keystone_phoenix, :jwt_issuer, "keystone"),
      "sub" => to_string(user.user_id),
      "username" => user.username,
      "isAdmin" => user.is_admin,
      "type" => token_type,
      "jti" => jti,
      "iat" => now,
      "exp" => now + ttl
    }

    token =
      private_jwk()
      |> JOSE.JWT.sign(%{"alg" => "RS256", "typ" => "JWT"}, claims)
      |> JOSE.JWS.compact()
      |> elem(1)

    {:ok, %{token: token, jti: jti, expires_in: ttl}}
  rescue
    error -> {:error, {:token_configuration, error}}
  end

  @spec verify(String.t(), String.t()) :: {:ok, map()} | {:error, :invalid_token}
  def verify(token, expected_type) when is_binary(token) do
    case JOSE.JWT.verify_strict(public_jwk(), ["RS256"], token) do
      {true, jwt, _jws} ->
        {_modules, claims} = JOSE.JWT.to_map(jwt)

        if valid_claims?(claims, expected_type) do
          {:ok, claims}
        else
          {:error, :invalid_token}
        end

      _ ->
        {:error, :invalid_token}
    end
  rescue
    _ -> {:error, :invalid_token}
  end

  def verify(_token, _expected_type), do: {:error, :invalid_token}

  @spec public_key_pem() :: binary()
  def public_key_pem do
    {_modules, pem} = JOSE.JWK.to_pem(public_jwk())
    pem
  end

  defp valid_claims?(claims, expected_type) do
    now = System.system_time(:second)

    claims["iss"] == Application.get_env(:keystone_phoenix, :jwt_issuer, "keystone") and
      claims["type"] == expected_type and
      is_binary(claims["sub"]) and
      is_binary(claims["jti"]) and
      is_integer(claims["exp"]) and
      claims["exp"] > now and
      is_integer(claims["iat"]) and
      claims["iat"] <= now + 5
  end

  defp private_jwk do
    case Application.get_env(:keystone_phoenix, :jwt_private_key) do
      nil -> generated_private_jwk()
      pem -> configured_jwk(@key_cache_key, pem)
    end
  end

  defp public_jwk do
    case Application.get_env(:keystone_phoenix, :jwt_public_key) do
      nil -> JOSE.JWK.to_public(private_jwk())
      pem -> configured_jwk(@public_key_cache_key, pem)
    end
  end

  defp configured_jwk(cache_key, pem) do
    pem = normalize_pem(pem)
    fingerprint = :crypto.hash(:sha256, pem)

    case :persistent_term.get(cache_key, nil) do
      {^fingerprint, jwk} ->
        jwk

      _ ->
        jwk = JOSE.JWK.from_pem(pem)
        :persistent_term.put(cache_key, {fingerprint, jwk})
        jwk
    end
  end

  defp generated_private_jwk do
    case :persistent_term.get(@key_cache_key, nil) do
      {:generated, jwk} ->
        jwk

      _ ->
        jwk = JOSE.JWK.generate_key({:rsa, 2048})
        :persistent_term.put(@key_cache_key, {:generated, jwk})
        jwk
    end
  end

  defp normalize_pem(pem) when is_binary(pem), do: String.replace(pem, "\\n", "\n")
end
