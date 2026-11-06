defmodule KeystonePhoenix.RateLimiterTest do
  use ExUnit.Case, async: false

  import Plug.Conn
  import Plug.Test

  alias KeystonePhoenix.RateLimiter
  alias KeystonePhoenixWeb.Plugs.NoRepeat
  alias KeystonePhoenixWeb.Plugs.RateLimit

  test "allows the configured number of attempts and returns a retry window" do
    key = "test-rate-#{System.unique_integer([:positive])}"
    on_exit(fn -> RateLimiter.delete(key) end)

    assert :allow = RateLimiter.check(key, 2, 60)
    assert :allow = RateLimiter.check(key, 2, 60)
    assert {:deny, retry_after} = RateLimiter.check(key, 2, 60)
    assert retry_after >= 1
  end

  test "rate limit plug returns a 429 response" do
    opts = RateLimit.init(key: "plug-test", limit: 1, window: 60, scope: :global)
    assert %{state: :unset} = RateLimit.call(conn(:get, "/rate-limit"), opts)
    assert %{state: :sent, status: 429} = RateLimit.call(conn(:get, "/rate-limit"), opts)
  end

  test "no-repeat plug keys submissions by user and action" do
    opts = NoRepeat.init(interval: 60)
    base = conn(:post, "/system/notices") |> assign(:current_user, %{user_id: 42})
    base = Map.put(base, :private, %{phoenix_action: :create})

    assert %{state: :unset} = NoRepeat.call(base, opts)
    assert %{state: :sent, status: 429} = NoRepeat.call(base, opts)
  end
end
