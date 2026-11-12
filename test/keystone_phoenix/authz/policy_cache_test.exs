defmodule KeystonePhoenix.Authz.PolicyCacheTest do
  use ExUnit.Case, async: false

  alias KeystonePhoenix.Authz.PolicyCache

  test "caches allow and deny decisions by role and permission" do
    key = "system:test:cache_#{System.unique_integer([:positive])}"
    assert :allow = PolicyCache.decision(901, key, fn -> :allow end)

    assert :allow =
             PolicyCache.decision(901, key, fn -> raise "cached decision was not reused" end)
  end

  test "does not cache authorization storage failures" do
    key = "system:test:error_#{System.unique_integer([:positive])}"

    assert {:error, :authorization_unavailable} =
             PolicyCache.decision(902, key, fn -> {:error, :authorization_unavailable} end)

    assert {:error, :authorization_unavailable} =
             PolicyCache.decision(902, key, fn -> {:error, :authorization_unavailable} end)
  end

  test "invalidating advances the version and clears decisions" do
    previous = PolicyCache.version()
    assert :ok = PolicyCache.invalidate()
    assert PolicyCache.version() == previous + 1
  end
end
