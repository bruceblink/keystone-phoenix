defmodule KeystonePhoenix.Auth.JwtKeyRegistryTest do
  use KeystonePhoenix.DataCase, async: false

  alias KeystonePhoenix.Auth.{JwtKey, JwtKeyRegistry, Token}

  setup do
    Repo.delete_all(JwtKey)
    {:ok, %{"keys" => [jwk]}} = Token.runtime_public_jwk_set()
    %{jwk: jwk}
  end

  test "bootstraps configured key and publishes only active keys", %{jwk: jwk} do
    assert {:ok, %{"keys" => [registered]}} = JwtKeyRegistry.public_jwk_set()
    assert registered["kty"] == "RSA"
    assert {:ok, _} = JwtKeyRegistry.register("retiring-key", jwk, status: "retiring")
    assert {:ok, %{"keys" => keys}} = JwtKeyRegistry.public_jwk_set()

    assert Enum.map(keys, & &1["kid"]) == [
             Application.get_env(:keystone_phoenix, :jwt_key_id),
             "retiring-key"
           ]
  end

  test "unknown kid is rejected and expired keys are not published", %{jwk: jwk} do
    expired = DateTime.add(DateTime.utc_now(), -1, :second)

    assert {:ok, _} =
             JwtKeyRegistry.register("expired-key", jwk, status: "retiring", expires_at: expired)

    assert JwtKeyRegistry.public_jwk_for("expired-key") == {:error, :unknown_key_id}
    assert JwtKeyRegistry.public_jwk_for("unknown-key") == {:error, :unknown_key_id}
  end

  test "activation retires the previous key and cleanup removes expired metadata", %{jwk: jwk} do
    assert {:ok, _} = JwtKeyRegistry.register("first-key", jwk, status: "active")
    assert {:ok, _} = JwtKeyRegistry.register("second-key", jwk, status: "retiring")
    assert {:ok, _} = JwtKeyRegistry.activate("second-key", 0)
    assert %JwtKey{status: "retiring"} = Repo.get_by(JwtKey, key_id: "first-key")
    assert %JwtKey{status: "active"} = Repo.get_by(JwtKey, key_id: "second-key")
    assert {:ok, %{retired: 1, deleted: 1}} = JwtKeyRegistry.retire_expired(0)
    assert is_nil(Repo.get_by(JwtKey, key_id: "first-key"))
  end
end
