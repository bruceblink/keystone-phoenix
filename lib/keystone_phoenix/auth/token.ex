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
  def access_ttl, do: Application.get_env(:keystone_phoenix, :jwt_access_ttl, 300)

  @spec refresh_ttl() :: pos_integer()
  def refresh_ttl, do: Application.get_env(:keystone_phoenix, :jwt_refresh_ttl, 1_209_600)

  @spec issue(map(), String.t(), String.t() | nil, pos_integer() | nil, String.t(), String.t()) ::
          {:ok, map()} | {:error, term()}
  def issue(
        user,
        token_type,
        session_id \\ nil,
        ttl_override \\ nil,
        authentication_level \\ "AAL1",
        client_id \\ "web"
      )
      when token_type in [@access_type, @refresh_type] do
    now = System.system_time(:second)
    ttl = token_ttl(token_type, ttl_override)
    jti = KeystonePhoenix.Identity.v7()
    permission_version = Map.get(user, :permission_version, 1)

    claims = %{
      "iss" => Application.get_env(:keystone_phoenix, :jwt_issuer, "keystone"),
      "aud" => Application.get_env(:keystone_phoenix, :jwt_audience, "keystone-api"),
      "sub" => to_string(user.user_id),
      "username" => user.username,
      "type" => token_type,
      "jti" => jti,
      "permission_version" => permission_version,
      "aal" => normalize_authentication_level(authentication_level),
      "amr" => authentication_methods(authentication_level),
      "client_id" => normalize_client_id(client_id),
      "iat" => now,
      "exp" => now + ttl
    }

    claims = if is_binary(session_id), do: Map.put(claims, "sid", session_id), else: claims

    token =
      private_jwk()
      |> JOSE.JWT.sign(
        %{
          "alg" => "RS256",
          "typ" => "JWT",
          "kid" => Application.get_env(:keystone_phoenix, :jwt_key_id, "keystone")
        },
        claims
      )
      |> JOSE.JWS.compact()
      |> elem(1)

    {:ok, %{token: token, jti: jti, expires_in: ttl}}
  rescue
    error -> {:error, {:token_configuration, error}}
  end

  @spec verify(String.t(), String.t()) :: {:ok, map()} | {:error, :invalid_token}
  def verify(token, expected_type) when is_binary(token) do
    case verification_jwk(token) do
      {:ok, key} -> verify_with_key(key, token, expected_type)
      :error -> {:error, :invalid_token}
    end
  end

  def verify(_token, _expected_type), do: {:error, :invalid_token}

  defp verify_with_key(key, token, expected_type) do
    case JOSE.JWT.verify_strict(key, ["RS256"], token) do
      {true, jwt, _jws} ->
        {_modules, claims} = JOSE.JWT.to_map(jwt)

        if valid_header?(token, key_id(token)) and valid_claims?(claims, expected_type) do
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

  defp token_ttl(token_type, nil) do
    if token_type == @access_type, do: access_ttl(), else: refresh_ttl()
  end

  defp token_ttl(_token_type, ttl) when is_integer(ttl) and ttl > 0, do: ttl
  defp token_ttl(_token_type, _ttl), do: raise(ArgumentError, "token ttl must be positive")

  defp normalize_authentication_level(value) when value in ["AAL1", "AAL2"], do: value

  defp normalize_authentication_level(_value),
    do: raise(ArgumentError, "invalid authentication level")

  defp authentication_methods("AAL2"), do: ["pwd", "otp"]
  defp authentication_methods("AAL1"), do: ["pwd"]

  defp normalize_client_id(value) when is_binary(value) do
    normalized = String.trim(value)

    if Regex.match?(~r/^[a-z0-9][a-z0-9._-]{0,63}$/, normalized),
      do: normalized,
      else: raise(ArgumentError, "invalid client id")
  end

  defp normalize_client_id(_value), do: raise(ArgumentError, "invalid client id")

  @spec public_key_pem() :: binary()
  def public_key_pem do
    {_modules, pem} = JOSE.JWK.to_pem(public_jwk())
    pem
  end

  @doc "按 RFC 7517 JWK Set 格式返回注册表中的 RSA 公钥。"
  @spec public_jwk_set() :: {:ok, map()} | {:error, term()}
  def public_jwk_set, do: KeystonePhoenix.Auth.JwtKeyRegistry.public_jwk_set()

  @doc "返回运行时配置的当前公钥，供注册表首次引导或数据库不可用时使用。"
  @spec runtime_public_jwk_set() :: {:ok, map()} | {:error, term()}
  def runtime_public_jwk_set do
    key_id = Application.get_env(:keystone_phoenix, :jwt_key_id, "keystone")

    if valid_key_id?(key_id) do
      {_fields, jwk} = JOSE.JWK.to_map(public_jwk())

      {:ok,
       %{
         "keys" => [
           Map.merge(jwk, %{
             "alg" => "RS256",
             "kid" => String.trim(key_id),
             "use" => "sig"
           })
         ]
       }}
    else
      {:error, :invalid_key_id}
    end
  rescue
    error -> {:error, {:jwk_configuration, error}}
  end

  @doc "Returns the public key as Base64 encoded X.509 SubjectPublicKeyInfo."
  @spec public_key_base64() :: binary()
  def public_key_base64 do
    :public_key.pem_entry_encode(:SubjectPublicKeyInfo, public_key())
    |> elem(1)
    |> Base.encode64()
  end

  @doc "Decrypts a Base64 encoded RSA/PKCS#1 login password."
  @spec decrypt_password(String.t()) :: {:ok, String.t()} | {:error, :invalid_password}
  def decrypt_password(password) when is_binary(password) and password != "" do
    with {:ok, encrypted} <- Base.decode64(password),
         decrypted <- :public_key.decrypt_private(encrypted, private_key()),
         true <- String.valid?(decrypted) do
      {:ok, decrypted}
    else
      _ -> {:error, :invalid_password}
    end
  rescue
    _ -> {:error, :invalid_password}
  end

  def decrypt_password(_password), do: {:error, :invalid_password}

  defp valid_claims?(claims, expected_type) do
    now = System.system_time(:second)

    claims["iss"] == Application.get_env(:keystone_phoenix, :jwt_issuer, "keystone") and
      audience_matches?(claims["aud"]) and
      claims["type"] == expected_type and
      is_binary(claims["sub"]) and
      is_binary(claims["jti"]) and
      is_integer(claims["permission_version"]) and
      is_integer(claims["exp"]) and
      claims["exp"] > now and
      is_integer(claims["iat"]) and
      claims["iat"] <= now + 5 and
      claims["aal"] in ["AAL1", "AAL2"] and
      is_list(claims["amr"]) and
      is_binary(claims["client_id"]) and
      is_binary(claims["sid"]) and KeystonePhoenix.Identity.canonical?(claims["sid"])
  end

  defp audience_matches?(audience) when is_binary(audience),
    do: audience == Application.get_env(:keystone_phoenix, :jwt_audience, "keystone-api")

  defp audience_matches?(audience) when is_list(audience),
    do: Application.get_env(:keystone_phoenix, :jwt_audience, "keystone-api") in audience

  defp audience_matches?(_audience), do: false

  defp valid_header?(token, expected_key_id) do
    with [encoded_header | _] <- String.split(token, "."),
         {:ok, header} <- Base.url_decode64(encoded_header, padding: false),
         {:ok, decoded} <- Jason.decode(header) do
      decoded["alg"] == "RS256" and decoded["typ"] == "JWT" and decoded["kid"] == expected_key_id
    else
      _ -> false
    end
  end

  defp verification_jwk(token) do
    key_id = key_id(token)

    ensure_result =
      if key_id == Application.get_env(:keystone_phoenix, :jwt_key_id, "keystone") do
        KeystonePhoenix.Auth.JwtKeyRegistry.ensure_current_runtime_key()
      else
        :ok
      end

    registry_result = KeystonePhoenix.Auth.JwtKeyRegistry.public_jwk_for(key_id)

    case {ensure_result, registry_result} do
      {{:error, {:registry_unavailable, _reason}}, _} ->
        if key_id == Application.get_env(:keystone_phoenix, :jwt_key_id, "keystone"),
          do: {:ok, public_jwk()},
          else: :error

      {{:error, _reason}, _} ->
        :error

      {:ok, {:ok, jwk_map}} ->
        {:ok, JOSE.JWK.from_map(jwk_map)}

      {:ok, {:error, :registry_unavailable}} ->
        if key_id == Application.get_env(:keystone_phoenix, :jwt_key_id, "keystone"),
          do: {:ok, public_jwk()},
          else: :error

      {:ok, {:error, :unknown_key_id}} ->
        if key_id == Application.get_env(:keystone_phoenix, :jwt_key_id, "keystone") do
          _ = KeystonePhoenix.Auth.JwtKeyRegistry.ensure_current_runtime_key()

          case KeystonePhoenix.Auth.JwtKeyRegistry.public_jwk_for(key_id) do
            {:ok, jwk_map} -> {:ok, JOSE.JWK.from_map(jwk_map)}
            _ -> :error
          end
        else
          :error
        end
    end
  end

  defp key_id(token) do
    with [encoded_header | _] <- String.split(token, "."),
         {:ok, header} <- Base.url_decode64(encoded_header, padding: false),
         {:ok, decoded} <- Jason.decode(header),
         key_id when is_binary(key_id) <- decoded["kid"] do
      key_id
    else
      _ -> ""
    end
  end

  defp private_jwk do
    case Application.get_env(:keystone_phoenix, :jwt_private_key) do
      nil -> generated_private_jwk()
      pem -> configured_jwk(@key_cache_key, pem)
    end
  end

  @doc "返回运行时配置的公钥 JWK。"
  def public_jwk do
    case Application.get_env(:keystone_phoenix, :jwt_public_key) do
      nil -> JOSE.JWK.to_public(private_jwk())
      pem -> configured_jwk(@public_key_cache_key, pem)
    end
  end

  defp public_key do
    public_jwk()
    |> JOSE.JWK.to_public_key()
    |> elem(1)
  end

  defp private_key do
    private_jwk()
    |> JOSE.JWK.to_key()
    |> elem(1)
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

  defp valid_key_id?(value) when is_binary(value) do
    Regex.match?(~r/^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$/, String.trim(value))
  end

  defp valid_key_id?(_value), do: false
end
