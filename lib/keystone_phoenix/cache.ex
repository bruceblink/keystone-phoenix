defmodule KeystonePhoenix.Cache do
  @moduledoc """
  Small Redis cache boundary with a database fallback.

  Cache failures are deliberately ignored so Redis availability does not make
  dictionary reads unavailable.
  """

  @redis_name KeystonePhoenix.Redis

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
  def put(key, value, ttl_seconds) do
    with {:ok, encoded} <- Jason.encode(value),
         {:ok, "OK"} <-
           Redix.command(@redis_name, ["SET", key, encoded, "EX", Integer.to_string(ttl_seconds)]) do
      :ok
    else
      _ -> :ok
    end
  rescue
    _ -> :ok
  end

  @spec delete(String.t()) :: :ok
  def delete(key) do
    Redix.command(@redis_name, ["DEL", key])
    :ok
  rescue
    _ -> :ok
  end

  defp get(key) do
    case Redix.command(@redis_name, ["GET", key]) do
      {:ok, nil} -> :miss
      {:ok, encoded} -> decode(encoded)
      _ -> :miss
    end
  rescue
    _ -> :miss
  end

  defp decode(encoded) do
    case Jason.decode(encoded) do
      {:ok, value} -> {:ok, value}
      _ -> :miss
    end
  end
end
