defmodule KeystonePhoenix.Auth.Passkey.ConfigTest do
  use ExUnit.Case, async: false

  alias KeystonePhoenix.Auth.Passkey.Config

  test "passkey is disabled by default" do
    assert Config.validate() == {:error, :passkey_disabled}
  end

  test "challenge ids are URL-safe and retain challenge bytes" do
    retained = %{bytes: :crypto.strong_rand_bytes(32)}
    id = KeystonePhoenix.Auth.Passkey.Challenge.id(retained)

    assert is_binary(id)
    assert Base.url_decode64!(id, padding: false) == retained.bytes
  end

  test "rejects a relying party outside the configured origin" do
    original = Application.get_env(:keystone_phoenix, :passkey)
    on_exit(fn -> Application.put_env(:keystone_phoenix, :passkey, original) end)

    Application.put_env(:keystone_phoenix, :passkey,
      enabled: true,
      rp_id: "example.com",
      origin: "https://login.example.net",
      rp_name: "Keystone Phoenix",
      user_verification: "required",
      challenge_ttl_seconds: 120
    )

    assert Config.validate() == {:error, :passkey_configuration}
  end
end
