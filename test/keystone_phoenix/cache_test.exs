defmodule KeystonePhoenix.CacheTest do
  use ExUnit.Case, async: false

  alias KeystonePhoenix.Cache

  test "caches values and invalidates a key prefix" do
    prefix = "cache-test-#{System.unique_integer([:positive])}-"
    first_key = prefix <> "first"
    second_key = prefix <> "second"

    assert :ok = Cache.put(first_key, %{value: 1}, 60)
    assert :ok = Cache.put(second_key, %{value: 2}, 60)
    assert %{value: 1} = Cache.fetch(first_key, 60, fn -> %{value: 9} end)

    assert :ok = Cache.delete_prefix(prefix)
    assert %{value: 9} = Cache.fetch(first_key, 60, fn -> %{value: 9} end)
    assert %{entries: entries} = Cache.stats()
    assert entries >= 1

    Cache.delete(first_key)
    Cache.delete(second_key)
  end
end
