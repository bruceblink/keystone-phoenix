defmodule KeystonePhoenix.Auth.OidcTestHttpClient do
  @moduledoc false

  def configure(id_token, jwks) do
    :persistent_term.put({__MODULE__, :id_token}, id_token)
    :persistent_term.put({__MODULE__, :jwks}, jwks)
  end

  def get(_url) do
    {:ok, 200, Jason.encode!(%{"keys" => :persistent_term.get({__MODULE__, :jwks})})}
  end

  def post(_url, form, _headers) do
    :persistent_term.put({__MODULE__, :form}, form)
    {:ok, 200, Jason.encode!(%{"id_token" => :persistent_term.get({__MODULE__, :id_token})})}
  end

  def last_form, do: :persistent_term.get({__MODULE__, :form})
end

defmodule KeystonePhoenixWeb.OidcControllerTest do
  use KeystonePhoenixWeb.ConnCase, async: false

  alias KeystonePhoenix.Auth.OidcTestHttpClient
  alias KeystonePhoenix.Repo
  alias KeystonePhoenix.User.SysUser

  @issuer "https://issuer.example"
  @client_id "oidc-client"

  setup do
    previous = Application.get_env(:keystone_phoenix, :oidc)

    Application.put_env(:keystone_phoenix, :oidc, oidc_config())

    on_exit(fn ->
      Application.put_env(:keystone_phoenix, :oidc, previous)
      :persistent_term.erase({OidcTestHttpClient, :id_token})
      :persistent_term.erase({OidcTestHttpClient, :jwks})
      :persistent_term.erase({OidcTestHttpClient, :form})
    end)

    {:ok, key: JOSE.JWK.generate_key({:rsa, 2048})}
  end

  test "starts an authorization code request with state, nonce, and S256 PKCE", %{conn: conn} do
    conn = get(conn, "/api/v1/auth/oidc/authorize")
    assert conn.status == 302

    query = redirect_query(conn)
    assert query["response_type"] == "code"
    assert query["client_id"] == @client_id
    assert query["code_challenge_method"] == "S256"
    assert byte_size(query["state"]) >= 32
    assert byte_size(query["nonce"]) >= 32
    assert byte_size(query["code_challenge"]) == 43
  end

  test "exchanges a provider code once and creates a local session", %{conn: conn, key: key} do
    user = insert_external_user("subject-123")
    conn = get(conn, "/api/v1/auth/oidc/authorize")
    query = redirect_query(conn)
    jwks = public_jwk(key)

    OidcTestHttpClient.configure(
      sign_id_token(key, %{
        "iss" => @issuer,
        "aud" => @client_id,
        "sub" => "subject-123",
        "nonce" => query["nonce"],
        "exp" => System.system_time(:second) + 300,
        "iat" => System.system_time(:second)
      }),
      [jwks]
    )

    callback = callback(conn, "provider-code", query["state"])
    assert callback.status == 200
    assert get_in(json_response(callback, 200), ["success"]) == true
    response = json_response(callback, 200)
    assert is_binary(get_in(response, ["data", "accessToken"]))
    refute Map.has_key?(response["data"], "token")
    assert URI.decode_query(OidcTestHttpClient.last_form())["code_verifier"]
    assert user.external_subject == "https://issuer.example:subject-123"

    replay = callback(conn, "provider-code", query["state"])
    assert replay.status == 401
    assert get_in(json_response(replay, 401), ["error", "code"]) == "invalid_credential"
  end

  test "rejects a callback with a mismatched state", %{conn: conn} do
    conn = get(conn, "/api/v1/auth/oidc/authorize")
    assert conn.status == 302

    rejected = callback(conn, "provider-code", "attacker-state")
    assert rejected.status == 401
    assert get_in(json_response(rejected, 401), ["error", "code"]) == "invalid_credential"
  end

  test "returns permission denied for an unmapped external subject", %{conn: conn, key: key} do
    conn = get(conn, "/api/v1/auth/oidc/authorize")
    query = redirect_query(conn)

    OidcTestHttpClient.configure(
      sign_id_token(key, %{
        "iss" => @issuer,
        "aud" => @client_id,
        "sub" => "unknown-subject",
        "nonce" => query["nonce"],
        "exp" => System.system_time(:second) + 300,
        "iat" => System.system_time(:second)
      }),
      [public_jwk(key)]
    )

    rejected = callback(conn, "provider-code-unmapped", query["state"])
    assert rejected.status == 403
    assert get_in(json_response(rejected, 403), ["error", "code"]) == "permission_denied"
  end

  test "rejects an expired ID token", %{conn: conn, key: key} do
    conn = get(conn, "/api/v1/auth/oidc/authorize")
    query = redirect_query(conn)

    OidcTestHttpClient.configure(
      sign_id_token(key, %{
        "iss" => @issuer,
        "aud" => @client_id,
        "sub" => "expired-subject",
        "nonce" => query["nonce"],
        "exp" => System.system_time(:second) - 1,
        "iat" => System.system_time(:second) - 300
      }),
      [public_jwk(key)]
    )

    rejected = callback(conn, "provider-code-expired", query["state"])
    assert rejected.status == 401
    assert get_in(json_response(rejected, 401), ["error", "code"]) == "invalid_credential"
  end

  test "rejects an ID token with a mismatched issuer or audience", %{key: key} do
    for {suffix, override} <- [
          {"issuer", %{"iss" => "https://other-issuer.example"}},
          {"audience", %{"aud" => "other-client"}}
        ] do
      conn = get(build_conn(), "/api/v1/auth/oidc/authorize")
      query = redirect_query(conn)

      claims = %{
        "iss" => @issuer,
        "aud" => @client_id,
        "sub" => "subject-" <> suffix,
        "nonce" => query["nonce"],
        "exp" => System.system_time(:second) + 300,
        "iat" => System.system_time(:second)
      }

      OidcTestHttpClient.configure(sign_id_token(key, Map.merge(claims, override)), [
        public_jwk(key)
      ])

      rejected = callback(conn, "provider-code-" <> suffix, query["state"])
      assert rejected.status == 401
      assert get_in(json_response(rejected, 401), ["error", "code"]) == "invalid_credential"
    end
  end

  test "reports disabled OIDC without contacting a provider", %{conn: conn} do
    Application.put_env(:keystone_phoenix, :oidc, Keyword.put(oidc_config(), :enabled, false))

    conn = get(conn, "/api/v1/auth/oidc/authorize")
    assert conn.status == 503
    assert get_in(json_response(conn, 503), ["error", "code"]) == "authorization_unavailable"
  end

  defp oidc_config do
    [
      enabled: true,
      issuer: @issuer,
      authorization_endpoint: "http://localhost:9999/authorize",
      token_endpoint: "http://localhost:9999/token",
      jwks_uri: "http://localhost:9999/jwks",
      client_id: @client_id,
      client_secret: "test-secret",
      redirect_uri: "http://localhost:4002/api/v1/auth/oidc/callback",
      audience: @client_id,
      scopes: ["openid", "profile", "email"],
      code_ttl_seconds: 300,
      auto_provision: false,
      http_client: OidcTestHttpClient
    ]
  end

  defp insert_external_user(subject) do
    %SysUser{}
    |> SysUser.create_changeset(%{
      username: "oidc_test_#{System.unique_integer([:positive])}",
      password: "Strong!123",
      status: 1
    })
    |> Ecto.Changeset.put_change(:external_subject, @issuer <> ":" <> subject)
    |> Ecto.Changeset.put_change(:external_user_id, @issuer)
    |> Repo.insert!()
  end

  defp redirect_query(conn) do
    conn
    |> get_resp_header("location")
    |> List.first()
    |> URI.parse()
    |> Map.fetch!(:query)
    |> URI.decode_query()
  end

  defp callback(conn, code, state) do
    query = URI.encode_query(%{"code" => code, "state" => state})
    get(conn, "/api/v1/auth/oidc/callback?" <> query)
  end

  defp public_jwk(key) do
    {_meta, jwk} = JOSE.JWK.to_map(JOSE.JWK.to_public(key))
    Map.put(jwk, "kid", "idp-key")
  end

  defp sign_id_token(key, claims) do
    key
    |> JOSE.JWT.sign(%{"alg" => "RS256", "kid" => "idp-key"}, claims)
    |> JOSE.JWS.compact()
    |> elem(1)
  end
end
