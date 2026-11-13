defmodule KeystonePhoenix.Authz.PolicyCacheTest do
  use ExUnit.Case, async: false

  alias KeystonePhoenix.Authz.PolicyCache

  test "caches allow and deny decisions by role and permission" do
    subject_id = "018f2a7e-5d3c-7b01-8a11-000000000901"
    key = "user:read:cache_#{System.unique_integer([:positive])}"
    assert :allow = PolicyCache.decision(subject_id, key, fn -> :allow end)

    assert :allow =
             PolicyCache.decision(subject_id, key, fn ->
               raise "cached decision was not reused"
             end)
  end

  test "does not cache authorization storage failures" do
    subject_id = "018f2a7e-5d3c-7b01-8a11-000000000902"
    key = "user:read:error_#{System.unique_integer([:positive])}"

    assert {:error, :authorization_unavailable} =
             PolicyCache.decision(subject_id, key, fn -> {:error, :authorization_unavailable} end)

    assert {:error, :authorization_unavailable} =
             PolicyCache.decision(subject_id, key, fn -> {:error, :authorization_unavailable} end)
  end

  test "invalidating advances the version and clears decisions" do
    previous = PolicyCache.version()
    assert :ok = PolicyCache.invalidate()
    assert PolicyCache.version() == previous + 1
  end
end
