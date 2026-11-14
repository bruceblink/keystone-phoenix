defmodule KeystonePhoenix.RateLimiterTest do
  use ExUnit.Case, async: false

  import Plug.Conn
  import Plug.Test

  alias KeystonePhoenix.RateLimiter
  alias KeystonePhoenix.RuntimeStore
  alias KeystonePhoenixWeb.Plugs.NoRepeat
  alias KeystonePhoenixWeb.Plugs.RateLimit

  test "allows the configured number of attempts and returns a retry window" do
    key = "test-rate-#{System.unique_integer([:positive])}"
    on_exit(fn -> RateLimiter.delete(key) end)

    assert :allow = RateLimiter.check(key, 2, 60)
    [{^key, 1, expires_at}] = :ets.lookup(RuntimeStore.rate_limit_table(), key)
    assert expires_at > System.monotonic_time(:millisecond)
    assert :allow = RateLimiter.check(key, 2, 60)
    [{^key, 2, ^expires_at}] = :ets.lookup(RuntimeStore.rate_limit_table(), key)
    assert {:deny, retry_after} = RateLimiter.check(key, 2, 60)
    assert retry_after >= 1
  end

  test "expired entries start a new future window and can be cleared around expiry" do
    table = RuntimeStore.rate_limit_table()
    expired_key = "test-expired-rate-#{System.unique_integer([:positive])}"
    clear_key = "test-clear-rate-#{System.unique_integer([:positive])}"
    now = System.monotonic_time(:millisecond)
    :ets.insert(table, {expired_key, 9, now - 1})
    :ets.insert(table, {clear_key, 1, now + 60_000})

    on_exit(fn ->
      RateLimiter.delete(expired_key)
      RateLimiter.delete(clear_key)
    end)

    assert [{^expired_key, 9, expired_at}] = :ets.lookup(table, expired_key)
    assert :allow = RateLimiter.check(expired_key, 1, 60)
    [{^expired_key, 1, new_expiration}] = :ets.lookup(table, expired_key)
    assert new_expiration > now
    assert new_expiration > expired_at
    assert {:deny, retry_after} = RateLimiter.check(expired_key, 1, 60)
    assert retry_after >= 1

    assert :ok = RateLimiter.delete(clear_key)
    assert [] = :ets.lookup(table, clear_key)
  end

  test "runtime cleanup removes expired rate-limit entries" do
    table = RuntimeStore.rate_limit_table()
    key = "test-sweep-rate-#{System.unique_integer([:positive])}"
    neighboring_key = "test-sweep-neighbor-rate-#{System.unique_integer([:positive])}"
    :ets.insert(table, {key, 1, System.monotonic_time(:millisecond) - 1})
    :ets.insert(table, {neighboring_key, 1, System.monotonic_time(:millisecond) + 60_000})

    on_exit(fn ->
      RateLimiter.delete(key)
      RateLimiter.delete(neighboring_key)
    end)

    assert [{^key, 1, _expired_at}] = :ets.lookup(table, key)

    send(RuntimeStore, :sweep)
    assert eventually?(fn -> :ets.lookup(table, key) == [] end, 100)
    assert [] = :ets.lookup(table, key)
    assert [{^neighboring_key, 1, _expires_at}] = :ets.lookup(table, neighboring_key)
  end

  test "concurrent first-window checks keep one shared count" do
    key = "test-first-concurrent-rate-#{System.unique_integer([:positive])}"
    on_exit(fn -> RateLimiter.delete(key) end)

    results = concurrent_checks(key, 32, 32, 60)

    assert Enum.count(results, &(&1 == :allow)) == 32
    assert Enum.all?(results, &(&1 == :allow))
    [{^key, 32, expires_at}] = :ets.lookup(RuntimeStore.rate_limit_table(), key)
    assert expires_at > System.monotonic_time(:millisecond)
  end

  test "concurrent checks after expiry replace the expired row only once" do
    key = "test-expired-concurrent-rate-#{System.unique_integer([:positive])}"
    table = RuntimeStore.rate_limit_table()
    :ets.insert(table, {key, 99, System.monotonic_time(:millisecond) - 1})
    on_exit(fn -> RateLimiter.delete(key) end)

    results = concurrent_checks(key, 48, 12, 60)

    assert Enum.count(results, &(&1 == :allow)) == 12
    assert Enum.count(results, &match?({:deny, _}, &1)) == 36
    [{^key, 48, expires_at}] = :ets.lookup(table, key)
    assert expires_at > System.monotonic_time(:millisecond)
  end

  test "cleans expired keys before enforcing the entry capacity" do
    previous_limit = Application.get_env(:keystone_phoenix, :rate_limit_max_entries)
    table = RuntimeStore.rate_limit_table()
    existing_entries = :ets.tab2list(table)
    Application.put_env(:keystone_phoenix, :rate_limit_max_entries, 1)
    :ets.delete_all_objects(table)

    expired_key = "test-capacity-expired-#{System.unique_integer([:positive])}"
    active_key = "test-capacity-active-#{System.unique_integer([:positive])}"
    rejected_key = "test-capacity-rejected-#{System.unique_integer([:positive])}"
    :ets.insert(table, {expired_key, 1, System.monotonic_time(:millisecond) - 1})

    on_exit(fn ->
      RateLimiter.delete(expired_key)
      RateLimiter.delete(active_key)
      RateLimiter.delete(rejected_key)

      if is_nil(previous_limit),
        do: Application.delete_env(:keystone_phoenix, :rate_limit_max_entries),
        else: Application.put_env(:keystone_phoenix, :rate_limit_max_entries, previous_limit)

      :ets.delete_all_objects(table)
      Enum.each(existing_entries, &:ets.insert(table, &1))
    end)

    assert :allow = RateLimiter.check(active_key, 1, 60)
    assert [] == :ets.lookup(table, expired_key)
    assert {:error, :capacity} = RateLimiter.check(rejected_key, 1, 60)
  end

  test "returns capacity instead of allowing a new key when the table is full" do
    previous_limit = Application.get_env(:keystone_phoenix, :rate_limit_max_entries)
    table = RuntimeStore.rate_limit_table()
    existing_entries = :ets.tab2list(table)
    Application.put_env(:keystone_phoenix, :rate_limit_max_entries, 1)
    :ets.delete_all_objects(table)

    active_key = "test-capacity-full-#{System.unique_integer([:positive])}"
    rejected_key = "test-capacity-full-rejected-#{System.unique_integer([:positive])}"
    assert :allow = RateLimiter.check(active_key, 1, 60)

    on_exit(fn ->
      RateLimiter.delete(active_key)
      RateLimiter.delete(rejected_key)

      if is_nil(previous_limit),
        do: Application.delete_env(:keystone_phoenix, :rate_limit_max_entries),
        else: Application.put_env(:keystone_phoenix, :rate_limit_max_entries, previous_limit)

      :ets.delete_all_objects(table)
      Enum.each(existing_entries, &:ets.insert(table, &1))
    end)

    assert {:error, :capacity} = RateLimiter.check(rejected_key, 1, 60)
  end

  test "rate limit plug returns a 429 response" do
    key = "plug-test-#{System.unique_integer([:positive])}"
    opts = RateLimit.init(key: key, limit: 1, window: 60, scope: :global)
    on_exit(fn -> RateLimiter.delete("rate:#{key}:global") end)

    assert %{state: :unset} = RateLimit.call(conn(:get, "/rate-limit"), opts)
    rejected = RateLimit.call(conn(:get, "/rate-limit"), opts)
    assert %{state: :sent, status: 429} = rejected
    assert [retry_after] = get_resp_header(rejected, "retry-after")
    assert String.to_integer(retry_after) >= 1
  end

  test "no-repeat plug keys submissions by user and action" do
    opts = NoRepeat.init(interval: 60)
    base = conn(:post, "/api/v1/notices") |> assign(:current_user, %{user_id: 42})
    base = Map.put(base, :private, %{phoenix_action: :create})

    assert %{state: :unset} = NoRepeat.call(base, opts)
    rejected = NoRepeat.call(base, opts)
    assert %{state: :sent, status: 429} = rejected
    assert [retry_after] = get_resp_header(rejected, "retry-after")
    assert String.to_integer(retry_after) >= 1
  end

  defp concurrent_checks(key, task_count, limit, window_seconds) do
    parent = self()

    tasks =
      for _ <- 1..task_count do
        Task.async(fn ->
          send(parent, {:ready, self()})

          receive do
            :start -> RateLimiter.check(key, limit, window_seconds)
          end
        end)
      end

    for _ <- tasks do
      assert_receive {:ready, _pid}, 5_000
    end

    Enum.each(tasks, &send(&1.pid, :start))
    Enum.map(tasks, &Task.await(&1, 5_000))
  end

  defp eventually?(check, attempts) do
    if check.() do
      true
    else
      if attempts > 1 do
        Process.sleep(1)
        eventually?(check, attempts - 1)
      else
        false
      end
    end
  end
end
