defmodule KeystonePhoenix.Cache do
  @moduledoc "Small ETS cache boundary for rebuildable application data."

  alias KeystonePhoenix.RuntimeStore

  @spec fetch(String.t(), pos_integer(), (-> term())) :: term()
  def fetch(key, ttl_seconds, loader) when is_function(loader, 0) do
    case get(key) do
      {:ok, value} ->
        value

      :miss ->
        value = loader.()
        put(key, value, ttl_seconds)
        value
    end
  end

  @spec put(String.t(), term(), pos_integer()) :: :ok
  def put(key, value, ttl_seconds) when is_binary(key) and is_integer(ttl_seconds) do
    :ets.insert(RuntimeStore.cache_table(), {key, value, expires_at(ttl_seconds)})
    :ok
  rescue
    _ -> :ok
  end

  @spec delete(String.t()) :: :ok
  def delete(key) do
    :ets.delete(RuntimeStore.cache_table(), key)
    :ok
  rescue
    _ -> :ok
  end

  @spec delete_prefix(String.t()) :: :ok
  def delete_prefix(prefix) when is_binary(prefix) do
    RuntimeStore.cache_table()
    |> :ets.tab2list()
    |> Enum.each(fn {key, _value, _expires_at} ->
      if String.starts_with?(key, prefix), do: :ets.delete(RuntimeStore.cache_table(), key)
    end)

    :ok
  rescue
    _ -> :ok
  end

  def delete_prefix(_prefix), do: :ok

  @doc "Returns the number of live ETS cache entries."
  def stats do
    %{entries: :ets.info(RuntimeStore.cache_table(), :size)}
  rescue
    _ -> %{entries: 0}
  end

  defp get(key) do
    current_time = now()

    case :ets.lookup(RuntimeStore.cache_table(), key) do
      [{^key, value, expires_at}] when expires_at > current_time ->
        {:ok, value}

      [{^key, _value, _expires_at}] ->
        :ets.delete(RuntimeStore.cache_table(), key)
        :miss

      [] ->
        :miss
    end
  rescue
    _ -> :miss
  end

  defp expires_at(ttl_seconds), do: now() + max(ttl_seconds, 1) * 1_000
  defp now, do: System.monotonic_time(:millisecond)
end
