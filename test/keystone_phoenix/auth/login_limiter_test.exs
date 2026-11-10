defmodule KeystonePhoenix.Auth.LoginLimiterTest do
  use ExUnit.Case, async: false

  alias KeystonePhoenix.Auth.LoginLimiter

  test "limits repeated attempts for one HTTP identity" do
    username = "login-limit-#{System.unique_integer([:positive])}"

    assert Enum.all?(1..10, fn _ ->
             LoginLimiter.check_http(username, {127, 0, 0, 1}) == :allow
           end)

    assert {:deny, retry_after} = LoginLimiter.check_http(username, {127, 0, 0, 1})
    assert retry_after >= 1
  end

  test "keeps HTTP identities isolated by address" do
    username = "login-address-#{System.unique_integer([:positive])}"

    assert :allow = LoginLimiter.check_http(username, {127, 0, 0, 1})
    assert :allow = LoginLimiter.check_http(username, {127, 0, 0, 2})
  end

  test "limits LiveView attempts by username" do
    username = "login-liveview-#{System.unique_integer([:positive])}"

    assert Enum.all?(1..10, fn _ -> LoginLimiter.check_liveview(username) == :allow end)
    assert {:deny, retry_after} = LoginLimiter.check_liveview(username)
    assert retry_after >= 1
  end
end
