defmodule KeystonePhoenix.RateLimiter do
  @moduledoc "Small per-node ETS rate limiter for public and idempotency-sensitive requests."

  alias KeystonePhoenix.RuntimeStore

  @default_max_entries 100_000

  @type result ::
          :allow
          | {:deny, pos_integer()}
          | {:error, :capacity | :unavailable}

  @doc "Allows at most `limit` attempts during one rolling window."
  @spec check(String.t(), pos_integer(), pos_integer()) :: result()
  def check(key, limit, window_seconds)
      when is_binary(key) and is_integer(limit) and limit > 0 and is_integer(window_seconds) and
             window_seconds > 0 do
    now = System.monotonic_time(:millisecond)
    window_expires_at = now + window_seconds * 1_000
    table = RuntimeStore.rate_limit_table()

    case :ets.lookup(table, key) do
      [] ->
        case new_key_result(table, key, window_expires_at, now) do
          :retry -> check(key, limit, window_seconds)
          result -> result
        end

      [{^key, _count, stored_expires_at}] when stored_expires_at <= now ->
        if replace_expired(table, key, stored_expires_at, window_expires_at) do
          :allow
        else
          check(key, limit, window_seconds)
        end

      [{^key, _count, stored_expires_at}] ->
        count = :ets.update_counter(table, key, {2, 1})
        if count <= limit, do: :allow, else: {:deny, retry_after(stored_expires_at, now)}
    end
  rescue
    _error -> {:error, :unavailable}
  end

  defp new_key_result(table, key, window_expires_at, now) do
    :global.trans({__MODULE__, :capacity}, fn ->
      sweep_expired(table, now)

      cond do
        :ets.info(table, :size) >= max_entries() ->
          {:error, :capacity}

        :ets.insert_new(table, {key, 1, window_expires_at}) ->
          :allow

        true ->
          :retry
      end
    end)
  end

  defp sweep_expired(table, now) do
    :ets.select_delete(table, [{{:"$1", :"$2", :"$3"}, [{:<, :"$3", now}], [true]}])
  end

  defp max_entries do
    case Application.get_env(:keystone_phoenix, :rate_limit_max_entries, @default_max_entries) do
      value when is_integer(value) and value > 0 -> value
      _ -> @default_max_entries
    end
  end

  defp replace_expired(table, key, stored_expires_at, window_expires_at) do
    match_spec = [
      {{key, :"$1", stored_expires_at}, [], [{{key, 1, window_expires_at}}]}
    ]

    :ets.select_replace(table, match_spec) == 1
  end

  @doc "Clears a key, primarily for deterministic tests and operational recovery."
  @spec delete(String.t()) :: :ok
  def delete(key) when is_binary(key) do
    :ets.delete(RuntimeStore.rate_limit_table(), key)
    :ok
  rescue
    _error -> :ok
  end

  defp retry_after(expires_at, now), do: max(div(expires_at - now + 999, 1_000), 1)
end
