defmodule KeystonePhoenix.Auth.Oidc.AuthorizationCodeTest do
  use KeystonePhoenix.DataCase, async: false

  alias KeystonePhoenix.Auth.Oidc.AuthorizationCode

  test "consumes a code once and rejects an expired code" do
    attrs = %{
      provider: "issuer.example",
      client_id: "oidc-client",
      redirect_uri: "http://localhost:4002/callback",
      state: "state-value",
      ttl_seconds: 300
    }

    assert :ok = AuthorizationCode.consume("one-time-code", attrs)

    assert {:error, :authorization_code_replayed} =
             AuthorizationCode.consume("one-time-code", attrs)

    assert {:error, :authorization_code_replayed} =
             AuthorizationCode.consume("expired-code", %{attrs | ttl_seconds: -1})
  end
end
