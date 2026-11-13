defmodule KeystonePhoenixWeb.JwkControllerTest do
  use KeystonePhoenixWeb.ConnCase, async: false

  alias KeystonePhoenix.Auth.Token

  test "publishes a standard public JWK Set", %{conn: conn} do
    response = get(conn, "/api/.well-known/jwks.json")
    %{"keys" => [key]} = json_response(response, 200)

    assert key["kty"] == "RSA"
    assert key["alg"] == "RS256"
    assert key["use"] == "sig"
    assert key["kid"] == Application.get_env(:keystone_phoenix, :jwt_key_id)
    assert is_binary(key["n"])
    assert key["n"] != ""
    assert key["e"] == "AQAB"
  end

  test "returns a unified unavailable response for an invalid key id", %{conn: conn} do
    original = Application.get_env(:keystone_phoenix, :jwt_key_id)
    Application.put_env(:keystone_phoenix, :jwt_key_id, "")
    on_exit(fn -> Application.put_env(:keystone_phoenix, :jwt_key_id, original) end)

    response = get(conn, "/api/.well-known/jwks.json")

    assert response.status == 503
    assert get_in(json_response(response, 503), ["error", "code"]) == "authorization_unavailable"
  end

  test "the JWK uses the same public key as token verification" do
    {:ok, %{"keys" => [key]}} = Token.public_jwk_set()
    assert key["kty"] == "RSA"
  end
end
