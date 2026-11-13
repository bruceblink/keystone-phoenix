defmodule KeystonePhoenix.Auth.TokenContractTest do
  use ExUnit.Case, async: false

  alias KeystonePhoenix.Auth.Token
  alias KeystonePhoenix.Identity

  setup do
    previous =
      Enum.into([:jwt_audience, :jwt_key_id, :jwt_access_ttl, :jwt_refresh_ttl], %{}, fn key ->
        {key, Application.get_env(:keystone_phoenix, key)}
      end)

    Application.put_env(:keystone_phoenix, :jwt_audience, "keystone-api")
    Application.put_env(:keystone_phoenix, :jwt_key_id, "test-key")
    Application.put_env(:keystone_phoenix, :jwt_access_ttl, 300)
    Application.put_env(:keystone_phoenix, :jwt_refresh_ttl, 1_209_600)

    on_exit(fn ->
      Enum.each(previous, fn {key, value} ->
        if is_nil(value),
          do: Application.delete_env(:keystone_phoenix, key),
          else: Application.put_env(:keystone_phoenix, key, value)
      end)
    end)

    :ok
  end

  test "issues matching cross-project claims and UUIDv7 identifiers" do
    user = %{user_id: Identity.v7(), username: "token_contract", permission_version: 7}
    session_id = Identity.v7()

    assert {:ok, access} = Token.issue(user, Token.access_type(), session_id)
    assert {:ok, refresh} = Token.issue(user, Token.refresh_type(), session_id)
    assert {:ok, access_claims} = Token.verify(access.token, Token.access_type())
    assert {:ok, refresh_claims} = Token.verify(refresh.token, Token.refresh_type())

    assert access_claims["aud"] == "keystone-api"
    assert refresh_claims["aud"] == "keystone-api"
    assert access_claims["sid"] == session_id
    assert refresh_claims["sid"] == session_id
    assert access_claims["permission_version"] == 7
    assert refresh_claims["permission_version"] == 7
    assert access_claims["exp"] - access_claims["iat"] == 300
    assert refresh_claims["exp"] - refresh_claims["iat"] == 1_209_600

    assert {:ok, bounded_refresh} =
             Token.issue(user, Token.refresh_type(), session_id, 37)

    assert {:ok, bounded_claims} = Token.verify(bounded_refresh.token, Token.refresh_type())
    assert bounded_claims["exp"] - bounded_claims["iat"] == 37

    assert Identity.canonical?(access_claims["jti"])
    assert Identity.canonical?(refresh_claims["jti"])

    [encoded_header | _] = String.split(access.token, ".")
    {:ok, header} = Base.url_decode64(encoded_header, padding: false)
    assert Jason.decode!(header)["kid"] == "test-key"
  end

  test "rejects tokens signed for a different audience or key id" do
    user = %{user_id: Identity.v7(), username: "token_contract", permission_version: 1}
    assert {:ok, token} = Token.issue(user, Token.access_type(), Identity.v7())

    Application.put_env(:keystone_phoenix, :jwt_audience, "another-api")
    assert {:error, :invalid_token} = Token.verify(token.token, Token.access_type())

    Application.put_env(:keystone_phoenix, :jwt_audience, "keystone-api")
    Application.put_env(:keystone_phoenix, :jwt_key_id, "another-key")
    assert {:error, :invalid_token} = Token.verify(token.token, Token.access_type())
  end

  test "requires a canonical session id on every token" do
    user = %{user_id: Identity.v7(), username: "token_contract", permission_version: 1}

    assert {:ok, token_without_session} = Token.issue(user, Token.refresh_type())

    assert {:error, :invalid_token} =
             Token.verify(token_without_session.token, Token.refresh_type())
  end
end
